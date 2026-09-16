import asyncio
import json
import logging
import os
import re
import time
from typing import Any, Literal

import openai
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from src.services.intent_rules import RuleOutcome, apply_rules


logger = logging.getLogger(__name__)


# 探针默认预算：启动 / 健康检查只等这么久，不能把启动拖住
DEFAULT_PROBE_TIMEOUT_MS = 10000


def describe_non_completion(response: Any) -> str:
    """把"不是 completion"的响应压成一行可读预览。

    事故教训（docs/plans/2026-09-15-intent-accuracy.md §15）：网关少写 `/v1` 时返回的是
    站点首页 HTML，而日志里只有 `non-completion response: str` —— 一眼看不出是打错了地址。
    带上预览就能直接看到 `<!doctype html>`。截断并折行，避免整页 HTML 淹掉日志。
    """
    if isinstance(response, (bytes, bytearray)):
        text = bytes(response).decode("utf-8", errors="replace")
    elif isinstance(response, str):
        text = response
    else:
        return f"<{type(response).__name__}>"
    flat = " ".join(text.split())
    if not flat:
        return "<empty>"
    return flat[:160] + ("…" if len(flat) > 160 else "")


def resolve_provider_config() -> tuple[str | None, str, str]:
    """解析 postprocess 的 (api_key, base_url, model)。

    `process()` 与 `check_provider()` 共用，避免探针与实际请求解析出不同配置
    —— 那样探针就会报"正常"而真实请求照样挂。
    """
    api_key = os.environ.get("ASR_POSTPROCESS_API_KEY") or os.environ.get("OPENAI_API_KEY")
    base_url = (
        os.environ.get("ASR_POSTPROCESS_BASE_URL")
        or os.environ.get("COACH_LLM_BASE_URL")
        or os.environ.get("OPENAI_BASE_URL")
        or "https://api.openai.com/v1"
    )
    model = (
        os.environ.get("ASR_POSTPROCESS_MODEL")
        or os.environ.get("COACH_LLM_MODEL")
        or "gpt-5.5"
    )
    return api_key, base_url, model


FallbackReason = Literal[
    "disabled",
    "missing_context",
    "missing_api_key",
    "timeout",
    "provider_error",
    "invalid_json",
    "schema_error",
    "non_dialogue_task",
]


# Per-turn intent label surfaced to the client. See ADR-0001.
# - provide:  player is filling the slot (or accepting/replacing a proposal)
# - delegate: player hands the slot back to the NPC ("你帮我起一个吧")
# - off_topic: not an answer to the current slot
# voice-service only labels the intent; completing a delegate is the client's job.
IntentLabel = Literal["provide", "delegate", "off_topic", "accept", "reject"]


class ExpectedSlot(BaseModel):
    model_config = ConfigDict(extra="allow")

    key: str
    type: str = "string"
    description: str | None = None


class ASRPostprocessContext(BaseModel):
    npc_question: str | None = None
    expected_slots: list[ExpectedSlot] = Field(default_factory=list)
    expected_answer_type: str | None = None
    target_intent: str | None = None
    intent_description: str | None = None
    candidate_answers: list[str] = Field(default_factory=list)
    recent_turns: list[dict[str, str]] = Field(default_factory=list)
    session_id: str | None = None
    user_id: str | None = None
    npc_id: str | None = None
    scene_id: str | None = None
    turn_id: str | None = None
    player_level: str | None = None
    language: str | None = None
    # 任务环境声明（由 Godot 场景传入）。非 "dialogue" 值表示非对话任务
    # （字母识别/单词朗读/回放自评/指令），voice-service 跳过对话 postprocess。
    task_mode: str | None = None


class ASRGuidanceOutput(BaseModel):
    npc_line: str | None = None


class LLMPostprocessOutput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    corrected_text: str
    correction_applied: bool
    correction_reason: str | None
    extracted: dict[str, str | int | float | bool | None] = Field(default_factory=dict)
    intent_matched: bool = True
    intent: IntentLabel | None = None
    guidance: ASRGuidanceOutput = Field(default_factory=ASRGuidanceOutput)
    confidence: float = Field(ge=0.0, le=1.0)


class ASRPostprocessResult(BaseModel):
    applied: bool
    corrected_text: str
    correction_reason: str | None
    extracted: dict[str, str | int | float | bool | None]
    intent_matched: bool
    intent: IntentLabel
    guidance: ASRGuidanceOutput
    confidence: float
    fallback_reason: FallbackReason | None
    model: str | None
    latency_ms: int
    # 实际发出的 provider 请求次数 - 1（0 = 首次即成）。降级为"容错放行"时，
    # 这个数字让运维能区分"第一次就失败"与"重试后仍失败"（§14.4）。
    retry_count: int = 0
    # ── 判据字段（ADR-0009 §3）：每个判决都要能说清"凭什么" ──
    #: "rule" | "llm"。降级放行（applied=False）时保持 None —— 降级不是判决。
    #: 规则层弃权时也是 "llm"：弃权后取值归零、意图仍由模型承担。
    verdict_source: str | None = None
    #: 规则层命中的规则名（可复核：能在玩家话语里指出那一段）。未命中为 None。
    matched_rule: str | None = None
    #: 规则层确认命中的候选值（与 extracted 里的值一致，便于客户端直接回显）
    matched_candidate: str | None = None
    # NOTE: 契约 §3 还列了 `shortcut_hit` / `shortcut_confidence`（是否走本地短路、未调 LLM）。
    # 本次落地**没有** LLM 之前的短路路径——规则层跑在模型之后，每次请求都已调用 LLM。
    # `RuleOutcome.shortcut_hit` 的含义是"取值由规则层给出"，与契约里的"未调 LLM"不是一回事，
    # 直接搬过来就是假判据，因此这两个字段暂不落地；将来真做本地短路时再加，并明确其含义。


def _merge_rule_extracted(
    model_extracted: dict[str, str | int | float | bool | None],
    outcome: RuleOutcome,
) -> dict[str, str | int | float | bool | None]:
    """把规则层结论合并进模型取值 —— **只动规则层实际处理的键**。

    规则层只推理 `expected_slots[0]`（见 `RuleOutcome.handled_key`）。因此不能整体替换
    `extracted`：多槽位上下文里，规则层没推理过的槽位必须保持模型原判。三种情形：

    - 意图被降级为非 provide → 整体清空（与既有 `intent != "provide"` 语义一致）
    - 规则层给出取值 → 按它处理的键覆盖
    - 规则层弃权（`extracted` 为空）→ **只清它处理的键**，其它槽位不动
    """
    if outcome.intent != "provide":
        return {}
    if outcome.extracted:
        merged = dict(model_extracted)
        merged.update(outcome.extracted)
        return merged
    key = outcome.handled_key
    if key is None:
        return dict(model_extracted)
    merged = dict(model_extracted)
    merged.pop(key, None)
    return merged


class ASRPostprocessor:
    def __init__(self, client: openai.AsyncOpenAI | None = None):
        # 调用方注入的客户端（测试 / 上层复用）：不缓存、不关闭，由注入方持有生命周期。
        self.client = client
        # 进程内复用的客户端：连接池复用，避免每请求新建 + 关闭（见 §11.3 F7）。
        self._cached_client: openai.AsyncOpenAI | None = None
        self._cached_key: tuple[str, str, int] | None = None
        self._retired_clients: list[openai.AsyncOpenAI] = []

    def _resolve_client(self, *, api_key: str, base_url: str, timeout_ms: int) -> openai.AsyncOpenAI:
        """取客户端：注入优先，否则按 (api_key, base_url, timeout) 复用同一个实例。

        这里全部是同步操作（无 await），在事件循环里天然原子，因此不需要加锁。
        配置变化（极少）时旧客户端进入 retired，由 `aclose()` 统一关闭。
        """
        if self.client is not None:
            return self.client
        key = (api_key, base_url, timeout_ms)
        if self._cached_client is None or self._cached_key != key:
            if self._cached_client is not None:
                self._retired_clients.append(self._cached_client)
            self._cached_client = openai.AsyncOpenAI(
                api_key=api_key,
                base_url=base_url,
                timeout=timeout_ms / 1000,
            )
            self._cached_key = key
            logger.info(
                "[ASR-POSTPROCESS] llm client created base_url=%s timeout_ms=%s",
                base_url,
                timeout_ms,
            )
        return self._cached_client

    async def aclose(self) -> None:
        """关闭本进程复用的客户端（服务关停时调用）。注入的客户端不在此列。"""
        clients = [
            client
            for client in [self._cached_client, *self._retired_clients]
            if client is not None
        ]
        self._cached_client = None
        self._cached_key = None
        self._retired_clients = []
        for client in clients:
            try:
                await client.close()
            except Exception:  # pragma: no cover - 关停路径不应抛错
                logger.debug("[ASR-POSTPROCESS] closing llm client failed", exc_info=True)

    async def check_provider(self, *, timeout_ms: int | None = None) -> dict[str, Any]:
        """启动期 / 健康检查用的 provider 探针。

        存在理由（docs/plans/2026-09-15-intent-accuracy.md §15.4）：F6 的守卫把 provider
        故障从"每个请求 500"变成了"安静降级"，于是意图判定可以整体失效而现场只有一行
        WARNING。这个探针让同一类故障在**启动 1 秒内**被喊出来，并暴露在 `/health` 里。

        绝不抛异常：探针失败不能把服务带崩，但必须能被看到。
        返回 {"status": "ok"|"error"|"disabled"|"missing_api_key", ...}
        """
        api_key, base_url, model = resolve_provider_config()
        info = {"model": model, "base_url": base_url}

        if os.environ.get("ASR_POSTPROCESS_ENABLED", "true").lower() == "false":
            return {"status": "disabled", "reason": "ASR_POSTPROCESS_ENABLED=false", **info}
        if not api_key:
            return {
                "status": "missing_api_key",
                "reason": "未配置 ASR_POSTPROCESS_API_KEY / OPENAI_API_KEY",
                **info,
            }

        # 探针必须用与真实请求**相同的 (base_url, timeout)** 键取客户端，
        # 否则会在缓存里多建一个客户端并把原来的挤退休；键不同探针也就失去代表性。
        request_timeout_ms = int(os.environ.get("ASR_POSTPROCESS_TIMEOUT_MS", "30000"))
        probe_budget_ms = timeout_ms or int(
            os.environ.get("ASR_POSTPROCESS_PROBE_TIMEOUT_MS", str(DEFAULT_PROBE_TIMEOUT_MS))
        )
        budget_ms = min(probe_budget_ms, request_timeout_ms)
        client = self._resolve_client(
            api_key=api_key, base_url=base_url, timeout_ms=request_timeout_ms
        )

        started = time.monotonic()
        try:
            completion = await asyncio.wait_for(
                client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": 'Reply with JSON: {"ok": true}'}],
                    response_format={"type": "json_object"},
                    temperature=0.0,
                    max_tokens=32,
                ),
                timeout=budget_ms / 1000,
            )
        except asyncio.TimeoutError:
            return {"status": "error", "reason": f"探针超时（{budget_ms}ms）", **info}
        except Exception as exc:  # noqa: BLE001 - 探针只负责描述，不负责抛
            return {"status": "error", "reason": f"{type(exc).__name__}: {str(exc)[:200]}", **info}

        latency_ms = int((time.monotonic() - started) * 1000)
        if not hasattr(completion, "choices"):
            # 典型：BASE_URL 少了 /v1 → 打到站点首页拿到 HTML。预览让现场一眼看出。
            return {
                "status": "error",
                "reason": "provider returned non-completion response: type=%s preview=%s"
                % (type(completion).__name__, describe_non_completion(completion)),
                "latency_ms": latency_ms,
                **info,
            }
        if not completion.choices:
            return {"status": "error", "reason": "provider returned empty choices",
                    "latency_ms": latency_ms, **info}
        return {"status": "ok", "latency_ms": latency_ms, **info}

    async def process(
        self,
        *,
        text: str,
        asr_confidence: float,
        language: str,
        context: dict[str, Any] | None,
    ) -> dict[str, Any]:
        logger.info(
            "[ASR-POSTPROCESS] start text_len=%s language=%s asr_confidence=%.4f context_present=%s",
            len(text),
            language,
            asr_confidence,
            bool(context),
        )
        if os.environ.get("ASR_POSTPROCESS_ENABLED", "true").lower() == "false":
            logger.info("[ASR-POSTPROCESS] fallback reason=disabled text_len=%s", len(text))
            return self._fallback(text, "disabled")

        if not context:
            logger.info("[ASR-POSTPROCESS] fallback reason=missing_context detail=empty text_len=%s", len(text))
            return self._fallback(text, "missing_context")

        try:
            parsed_context = ASRPostprocessContext.model_validate(context)
        except ValidationError as exc:
            logger.info(
                "[ASR-POSTPROCESS] fallback reason=missing_context detail=validation_error error_count=%s text_len=%s",
                len(exc.errors()),
                len(text),
            )
            return self._fallback(text, "missing_context")

        # 非对话任务（字母识别/单词朗读/回放自评/指令）：由场景声明 task_mode，
        # voice-service 不做对话意图判定，跳过 LLM，原样透传文本供客户端本地分类。
        # 见 CONTEXT.md「交互意图与槽位」——委托/槽位只适用于对话题。
        if parsed_context.task_mode and parsed_context.task_mode != "dialogue":
            logger.info(
                "[ASR-POSTPROCESS] skip reason=non_dialogue_task task_mode=%s text_len=%s",
                parsed_context.task_mode,
                len(text),
            )
            return self._fallback(text, "non_dialogue_task")

        # 上下文充分判定：npc_question / expected_slots / candidate_answers 任一存在
        # 即视为可处理。封闭题（candidate_answers）即使没有 npc_question/expected_slots
        # 也应进入 LLM 路径做纠错与意图识别，而非一刀切 fallback。
        context_sufficient = (
            bool(parsed_context.npc_question)
            or len(parsed_context.expected_slots) > 0
            or len(parsed_context.candidate_answers) > 0
        )
        if not context_sufficient:
            logger.info(
                "[ASR-POSTPROCESS] fallback reason=missing_context detail=incomplete_context npc_question_present=%s expected_slot_count=%s candidate_answer_count=%s text_len=%s",
                bool(parsed_context.npc_question),
                len(parsed_context.expected_slots),
                len(parsed_context.candidate_answers),
                len(text),
            )
            return self._fallback(text, "missing_context")

        api_key, base_url, model = resolve_provider_config()
        if not api_key:
            logger.info("[ASR-POSTPROCESS] fallback reason=missing_api_key text_len=%s", len(text))
            return self._fallback(text, "missing_api_key")

        timeout_ms = int(os.environ.get("ASR_POSTPROCESS_TIMEOUT_MS", "30000"))
        max_tokens = int(os.environ.get("ASR_POSTPROCESS_MAX_TOKENS", "2048"))
        # 网关 5xx / 连接错误的一次有界重试（§14.4）。默认 1 次、带 300ms 退避；
        # 设 ASR_POSTPROCESS_MAX_RETRIES=0 可关闭。重试不延长总时长预算（见 _call_llm_with_retry）。
        max_retries = max(0, int(os.environ.get("ASR_POSTPROCESS_MAX_RETRIES", "1")))
        retry_backoff_ms = max(0, int(os.environ.get("ASR_POSTPROCESS_RETRY_BACKOFF_MS", "300")))
        attempt_log: dict[str, int] = {"attempts": 0}
        started = time.monotonic()
        logger.info(
            "[ASR-POSTPROCESS] context npc_question_present=%s npc_question_len=%s expected_answer_type=%s expected_slot_count=%s expected_slot_keys=%s target_intent=%s intent_description_present=%s candidate_answer_count=%s recent_turn_count=%s session_present=%s user_present=%s npc_id=%s scene_id=%s turn_present=%s player_level=%s",
            bool(parsed_context.npc_question),
            len(parsed_context.npc_question or ""),
            parsed_context.expected_answer_type,
            len(parsed_context.expected_slots),
            [slot.key for slot in parsed_context.expected_slots],
            parsed_context.target_intent,
            bool(parsed_context.intent_description),
            len(parsed_context.candidate_answers),
            len(parsed_context.recent_turns),
            bool(parsed_context.session_id),
            bool(parsed_context.user_id),
            parsed_context.npc_id,
            parsed_context.scene_id,
            bool(parsed_context.turn_id),
            parsed_context.player_level,
        )
        logger.info(
            "[ASR-POSTPROCESS] provider request base_url=%s model=%s timeout_ms=%s text_len=%s",
            base_url,
            model,
            timeout_ms,
            len(text),
        )

        try:
            # timeout_ms 是**总时长预算**：httpx 的超时是分阶段读超时，不是总时长上限，
            # 实测曾出现单次 37.8s 超过配置的 30s（§11.3 F7）。这里用截止时间兜总时长，
            # 覆盖 finish_reason=length 的重试与 §14.4 的瞬时故障重试在内。
            llm_payload = await self._call_llm_with_retry(
                deadline=time.monotonic() + timeout_ms / 1000,
                max_retries=max_retries,
                backoff_ms=retry_backoff_ms,
                attempt_log=attempt_log,
                api_key=api_key,
                base_url=base_url,
                model=model,
                text=text,
                asr_confidence=asr_confidence,
                language=language,
                context=parsed_context,
                timeout_ms=timeout_ms,
                max_tokens=max_tokens,
            )
        except openai.APITimeoutError:
            logger.warning(
                "[ASR-POSTPROCESS] provider timeout base_url=%s model=%s timeout_ms=%s attempts=%s",
                base_url,
                model,
                timeout_ms,
                attempt_log["attempts"],
            )
            return self._fallback(
                text, "timeout", latency_ms=timeout_ms, retry_count=attempt_log["attempts"] - 1
            )
        except asyncio.TimeoutError:
            logger.warning(
                "[ASR-POSTPROCESS] llm total budget exceeded budget_ms=%s base_url=%s model=%s attempts=%s",
                timeout_ms,
                base_url,
                model,
                attempt_log["attempts"],
            )
            return self._fallback(
                text, "timeout", latency_ms=timeout_ms, retry_count=attempt_log["attempts"] - 1
            )
        except openai.APIStatusError as exc:
            message = getattr(exc, "message", str(exc))[:500]
            logger.warning(
                "[ASR-POSTPROCESS] provider api_status_error base_url=%s model=%s status_code=%s attempts=%s message=%r",
                base_url,
                model,
                getattr(exc, "status_code", None),
                attempt_log["attempts"],
                message,
            )
            return self._fallback(
                text,
                "provider_error",
                latency_ms=self._elapsed_ms(started),
                retry_count=attempt_log["attempts"] - 1,
            )
        except openai.APIError as exc:
            message = getattr(exc, "message", str(exc))[:500]
            logger.warning(
                "[ASR-POSTPROCESS] provider api_error base_url=%s model=%s error_type=%s attempts=%s message=%r",
                base_url,
                model,
                exc.__class__.__name__,
                attempt_log["attempts"],
                message,
            )
            return self._fallback(
                text,
                "provider_error",
                latency_ms=self._elapsed_ms(started),
                retry_count=attempt_log["attempts"] - 1,
            )
        except RuntimeError as exc:
            logger.warning(
                "[ASR-POSTPROCESS] provider runtime_error model=%s attempts=%s error=%s",
                model,
                attempt_log["attempts"],
                str(exc),
            )
            return self._fallback(
                text,
                "provider_error",
                latency_ms=self._elapsed_ms(started),
                retry_count=attempt_log["attempts"] - 1,
            )

        try:
            parsed = json.loads(llm_payload)
        except json.JSONDecodeError as exc:
            logger.info(
                "[ASR-POSTPROCESS] fallback reason=invalid_json error=%s payload_len=%s",
                str(exc),
                len(llm_payload),
            )
            return self._fallback(text, "invalid_json", latency_ms=self._elapsed_ms(started))

        if not isinstance(parsed, dict):
            logger.info(
                "[ASR-POSTPROCESS] fallback reason=schema_error detail=non_object payload_type=%s payload_len=%s",
                type(parsed).__name__,
                len(llm_payload),
            )
            return self._fallback(text, "schema_error", latency_ms=self._elapsed_ms(started))

        logger.info(
            "[ASR-POSTPROCESS] provider response keys=%s payload_len=%s",
            sorted(parsed.keys()),
            len(llm_payload),
        )

        try:
            output = LLMPostprocessOutput.model_validate(parsed)
        except ValidationError as exc:
            logger.info(
                "[ASR-POSTPROCESS] fallback reason=schema_error error_count=%s payload_keys=%s",
                len(exc.errors()),
                sorted(parsed.keys()),
            )
            return self._fallback(text, "schema_error", latency_ms=self._elapsed_ms(started))

        model_intent = output.intent or ("provide" if output.intent_matched else "off_topic")
        model_extracted = {} if model_intent != "provide" else self._filter_extracted(output.extracted, parsed_context)
        logger.info(
            "[ASR-POSTPROCESS] extracted raw_keys=%s filtered_keys=%s allowed_keys=%s",
            sorted(output.extracted.keys()),
            sorted(model_extracted.keys()),
            [slot.key for slot in parsed_context.expected_slots],
        )

        # ── 规则层（ADR-0009 §4）：取值规范化，外加三处**窄口径合法性归一** ──
        # **两个文本，各司其职**：决策（命中判定/召回边界/撤回/合法性归一）用原始 ASR 文本 `text`，
        # 只有自由槽的**表面形式**用模型的 corrected_text。混用会出事——实测教训：
        # 模型已把孩子的学习错误（「Nice meet you」）纠成正确句子，规则层若在 corrected_text 上判定，
        # 就会确认出一个"完美命中"，把学习错误改写成满分答案（rule_004 明令禁止）。
        # 意图判定仍归模型（rule_003）；规则层只在 ADR §1 例外列出的三处降级为 off_topic。
        outcome = apply_rules(
            text=text,
            context=parsed_context.model_dump(exclude_none=True),
            model_intent=model_intent,
            model_extracted=model_extracted,
            corrected_text=output.corrected_text,
        )
        intent = outcome.intent
        extracted = _merge_rule_extracted(model_extracted, outcome)
        intent_matched = intent == "provide"
        # guidance 依赖**最终**意图：delegate 被合法性归一降级为 off_topic 后，
        # 代选建议必须一起丢掉，否则客户端会收到一个没有消费者的提议。
        guidance = ASRGuidanceOutput() if intent == "delegate" else self._filter_guidance(output.guidance, parsed_context)

        if outcome.intent != model_intent or extracted != model_extracted:
            logger.info(
                "[ASR-POSTPROCESS] rule layer intent=%s→%s extracted_keys=%s→%s verdict_source=%s matched_rule=%s matched_candidate=%s notes=%s",
                model_intent,
                intent,
                sorted(model_extracted.keys()),
                sorted(extracted.keys()),
                outcome.verdict_source,
                outcome.matched_rule,
                outcome.matched_candidate,
                outcome.notes,
            )
        result = ASRPostprocessResult(
            applied=True,
            corrected_text=output.corrected_text,
            correction_reason=output.correction_reason,
            extracted=extracted,
            intent_matched=intent_matched,
            intent=intent,
            guidance=guidance,
            confidence=output.confidence,
            fallback_reason=None,
            model=model,
            latency_ms=self._elapsed_ms(started),
            retry_count=attempt_log["attempts"] - 1,
            verdict_source=outcome.verdict_source,
            matched_rule=outcome.matched_rule,
            matched_candidate=outcome.matched_candidate,
        )
        dumped = result.model_dump()
        logger.info(
            "[ASR-POSTPROCESS] success corrected_text_len=%s correction_applied=%s correction_reason_present=%s intent_matched=%s intent=%s guidance_present=%s confidence=%.4f latency_ms=%s model=%s",
            len(dumped["corrected_text"]),
            output.correction_applied,
            bool(dumped["correction_reason"]),
            dumped["intent_matched"],
            dumped["intent"],
            bool(dumped["guidance"].get("npc_line")),
            dumped["confidence"],
            dumped["latency_ms"],
            dumped["model"],
        )
        return dumped

    async def _call_llm(
        self,
        *,
        api_key: str,
        base_url: str,
        model: str,
        text: str,
        asr_confidence: float,
        language: str,
        context: ASRPostprocessContext,
        timeout_ms: int,
        max_tokens: int,
    ) -> str:
        client = self._resolve_client(
            api_key=api_key,
            base_url=base_url,
            timeout_ms=timeout_ms,
        )
        user_prompt = self._user_prompt(text, asr_confidence, language, context)
        logger.info(
            "[ASR-POSTPROCESS] llm request model=%s prompt_len=%s raw_text_len=%s expected_slot_count=%s candidate_answer_count=%s recent_turn_count=%s",
            model,
            len(user_prompt),
            len(text),
            len(context.expected_slots),
            len(context.candidate_answers),
            len(context.recent_turns),
        )
        messages = [
            {"role": "system", "content": self._system_prompt()},
            {"role": "user", "content": user_prompt},
        ]
        logger.info(
            "[ASR-POSTPROCESS] llm input content=%s",
            json.dumps(messages, ensure_ascii=False, default=str),
        )

        content, raw_completion, finish_reason = await self._complete_json(
            client, model, messages, max_tokens
        )
        if finish_reason == "length":
            retry_tokens = max(max_tokens * 2, 2048)
            logger.warning(
                "[ASR-POSTPROCESS] llm finish_reason=length max_tokens=%s reasoning_truncated; retrying with max_tokens=%s",
                max_tokens,
                retry_tokens,
            )
            content, raw_completion, finish_reason = await self._complete_json(
                client, model, messages, retry_tokens
            )
        logger.info(
            "[ASR-POSTPROCESS] llm raw_completion=%s",
            json.dumps(raw_completion, ensure_ascii=False, default=str),
        )
        logger.info(
            "[ASR-POSTPROCESS] llm raw_response_present=%s raw_response_len=%s finish_reason=%s",
            isinstance(content, str) and bool(content),
            len(content) if isinstance(content, str) else 0,
            finish_reason,
        )
        if not isinstance(content, str) or not content:
            local_payload = self._local_empty_content_fallback(text, context)
            if local_payload:
                logger.info("[ASR-POSTPROCESS] llm empty content recovered locally")
                return local_payload
            raise RuntimeError("Empty LLM response")
        return content

    async def _complete_json(
        self,
        client: openai.AsyncOpenAI,
        model: str,
        messages: list[dict[str, str]],
        max_tokens: int,
    ) -> tuple[str | None, dict[str, Any], str | None]:
        completion = await client.chat.completions.create(
            model=model,
            messages=messages,
            response_format={"type": "json_object"},
            temperature=0.1,
            max_tokens=max_tokens,
        )
        # 网关/代理形状漂移时 SDK 可能返回非 completion 对象（典型：BASE_URL 少了 /v1，
        # 请求打到站点首页拿到 HTML 且 HTTP 200，SDK 于是返回 str）。
        # 直接取 .choices 会抛 AttributeError，而 process() 只捕获
        # APITimeoutError / APIStatusError / APIError / RuntimeError，异常会冒泡成 ASR 端点 500。
        # 这里转成 RuntimeError，复用既有的 provider_error 降级分支（容错放行）。
        # 见 docs/plans/2026-09-15-intent-accuracy.md §11.3 F6。
        # 预览是给现场排障用的：网关少写 /v1 时会直接看到站点首页内容（§15）。
        if not hasattr(completion, "choices"):
            raise RuntimeError(
                "provider returned non-completion response: type=%s preview=%s"
                % (type(completion).__name__, describe_non_completion(completion))
            )
        choice = completion.choices[0] if completion.choices else None
        content = choice.message.content if choice else None
        finish_reason = choice.finish_reason if choice else None
        return content, completion.model_dump(mode="json"), finish_reason

    def _local_empty_content_fallback(self, text: str, context: ASRPostprocessContext) -> str | None:
        if context.expected_answer_type != "player_name":
            return None
        slot = next((slot for slot in context.expected_slots if slot.type == "person_name"), None)
        if not slot:
            return None
        name = self._extract_local_player_name(text)
        if not name:
            return None
        corrected_text = f"我叫{name}"
        return json.dumps(
            {
                "corrected_text": corrected_text,
                "correction_applied": corrected_text != text,
                "correction_reason": "LLM returned empty content; extracted clear player name locally.",
                "extracted": {slot.key: name},
                "intent_matched": True,
                "intent": "provide",
                "guidance": {"npc_line": None},
                "confidence": 0.75,
            },
            ensure_ascii=False,
        )

    def _extract_local_player_name(self, text: str) -> str | None:
        cleaned = re.sub(r"[\s。.!！?？,，、；;：:]+", " ", text).strip()
        match = re.search(r"(?:我叫|叫我|我是)([一-鿿A-Za-z]{1,12})", cleaned)
        if not match:
            return None
        candidate = match.group(1)
        candidate = re.split(r"(?:你|谁|什么|哪里|怎么|吗|呢|吧|呀|啊)", candidate, maxsplit=1)[0]
        candidate = candidate[:2] if len(candidate) >= 3 and candidate[0:2] == candidate[-2:] else candidate
        candidate = re.split(r"(?:大小的|小小的|大大的|的)", candidate, maxsplit=1)[0]
        return candidate if 1 <= len(candidate) <= 6 else None

    def _filter_extracted(
        self,
        extracted: dict[str, str | int | float | bool | None],
        context: ASRPostprocessContext,
    ) -> dict[str, str | int | float | bool | None]:
        allowed_keys = {slot.key for slot in context.expected_slots}
        return {key: value for key, value in extracted.items() if key in allowed_keys}

    def _filter_guidance(
        self,
        guidance: ASRGuidanceOutput,
        context: ASRPostprocessContext,
    ) -> ASRGuidanceOutput:
        if not guidance.npc_line or not self._confirmation_already_asked(context):
            return guidance
        return ASRGuidanceOutput()

    def _confirmation_already_asked(self, context: ASRPostprocessContext) -> bool:
        npc_turns = [turn.get("text", "") for turn in context.recent_turns if turn.get("speaker") == "npc"]
        return any(self._looks_like_confirmation(text) for text in npc_turns)

    def _looks_like_confirmation(self, text: str) -> bool:
        normalized = text.lower()
        confirmation_markers = ["没听明白", "没听清", "怎么拼", "拼写", "是不是", "确认", "confirm", "spell", "did you say"]
        return any(marker in normalized for marker in confirmation_markers)

    def _fallback(
        self,
        text: str,
        reason: FallbackReason,
        latency_ms: int = 0,
        retry_count: int = 0,
    ) -> dict[str, Any]:
        # missing_context: 上下文不充分，无法判定意图，不应声称玩家提供了槽位值
        #   （applied=False 与 intent_matched=True 自相矛盾）。
        # 其他系统故障（disabled/timeout/provider_error/...）: 保持容错放行，
        #   让客户端用原始文本继续，避免网络抖动误判为玩家未作答。
        tolerate = reason != "missing_context"
        return ASRPostprocessResult(
            applied=False,
            corrected_text=text,
            correction_reason=None,
            extracted={},
            intent_matched=tolerate,
            intent="provide" if tolerate else "off_topic",
            guidance=ASRGuidanceOutput(),
            confidence=0.0,
            fallback_reason=reason,
            model=None,
            latency_ms=latency_ms,
            retry_count=retry_count,
        ).model_dump()

    def _elapsed_ms(self, started: float) -> int:
        return int((time.monotonic() - started) * 1000)

    @staticmethod
    def _is_retryable_provider_error(exc: BaseException) -> bool:
        """只有"瞬时"的 provider 故障才值得重试。

        重试白名单：5xx、连接错误。
        刻意不重试：
        - 超时（`APITimeoutError` 是 `APIConnectionError` 的子类，**必须先排除**）——
          它已经吃掉了孩子的等待与预算；
        - 4xx —— 配置/鉴权错误，重试只会掩盖它；
        - 响应形状漂移（走 `RuntimeError` 分支，如 F6 的 HTML 200）—— 那是配置问题，不是抖动。
        """
        if isinstance(exc, openai.APITimeoutError):
            return False
        if isinstance(exc, openai.APIStatusError):
            status = getattr(exc, "status_code", None)
            return isinstance(status, int) and status >= 500
        return isinstance(exc, openai.APIConnectionError)

    async def _call_llm_with_retry(
        self,
        *,
        deadline: float,
        max_retries: int,
        backoff_ms: int,
        attempt_log: dict[str, int],
        **kwargs: Any,
    ) -> str:
        """在**同一个总时长预算**内调用 LLM；瞬时故障按 `max_retries` 有界重试。

        `deadline` 是绝对时间点（`time.monotonic()`）。每次尝试只取剩余预算，
        所以**重试永远不会延长孩子等待的上限**——这是本方案的核心安全性质
        （否则"重试"会把 30s 预算变成 60s）。
        """
        attempt = 0
        while True:
            attempt_log["attempts"] = attempt + 1
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise asyncio.TimeoutError
            try:
                return await asyncio.wait_for(self._call_llm(**kwargs), timeout=remaining)
            except (openai.APIError, asyncio.TimeoutError) as exc:
                if attempt >= max_retries or not self._is_retryable_provider_error(exc):
                    raise
                delay_s = min(
                    backoff_ms / 1000 * (attempt + 1),
                    max(0.0, deadline - time.monotonic()),
                )
                logger.warning(
                    "[ASR-POSTPROCESS] provider transient failure; retry attempt=%s/%s delay_ms=%s error_type=%s status_code=%s remaining_ms=%s",
                    attempt + 1,
                    max_retries,
                    int(delay_s * 1000),
                    exc.__class__.__name__,
                    getattr(exc, "status_code", None),
                    int(max(0.0, deadline - time.monotonic()) * 1000),
                )
                attempt += 1
                if delay_s > 0:
                    await asyncio.sleep(delay_s)

    def _system_prompt(self) -> str:
        return (
            "You are an ASR post-processor for a children's language-learning RPG. "
            "Return one JSON object only. No reasoning. No markdown. "
            "Required keys: corrected_text, correction_applied, correction_reason, extracted, intent_matched, intent, guidance, confidence. "
            "intent must be one of: provide, delegate, off_topic, accept, reject. "
            "Use provide when the player supplies a slot value or accepts/replaces a previous proposal. "
            "Use delegate when the player asks the NPC to choose from the slot's value pool, for example 你帮我起一个吧 or 随便选一个. "
            "Use delegate only when the expected slot declares delegatable true; if the slot is not delegatable, treat such an utterance as off_topic. "
            "Use off_topic when the player does not answer the current slot. "
            "Use accept only when the slot's slot_state is proposed and the player agrees to the proposed_value. "
            "Use reject only when the slot's slot_state is proposed and the player declines the proposed_value or asks for a different one. "
            "Never use accept or reject when no slot has slot_state proposed: without a proposal there is nothing to agree or disagree with, so use off_topic instead. "
            "If the player merely repeats something they already said (see recent_turns) instead of answering the current question, use off_topic. "
            "Filler-only utterances such as 嗯, 呃, 哦, um, uh are off_topic; never guess a slot value from them. "
            "For delegate, accept or reject, leave extracted empty and set intent_matched false. "
            "For delegate, also do not write a proposal in guidance.npc_line. "
            "guidance must be an object with npc_line. confidence must be 0..1. "
            "Correct ASR errors only when context strongly supports it. "
            "Extract only expected_slots keys. Do not invent extra keys. "
            "For candidate_answers closed-set questions, prefer candidate_answers. "
            "Decide whether raw_text satisfies target_intent and intent_description. "
            "If confidence is low or the answer is implausible, do not accept the slot immediately. "
            "Ask at most one confirmation question, such as: 我有点没听明白，是 Google 吗？怎么拼写呢？ "
            "If confirmation_already_asked is true, do not ask another confirmation question. "
            "Do not invent slot values when intent is not matched."
        )

    def _user_prompt(
        self,
        text: str,
        asr_confidence: float,
        language: str,
        context: ASRPostprocessContext,
    ) -> str:
        payload = context.model_dump(exclude_none=True)
        return json.dumps(
            {
                "raw_text": text,
                "asr_confidence": asr_confidence,
                "language": language,
                "npc_question": payload.get("npc_question"),
                "expected_slots": payload.get("expected_slots", []),
                "expected_answer_type": payload.get("expected_answer_type"),
                "target_intent": payload.get("target_intent"),
                "intent_description": payload.get("intent_description"),
                "candidate_answers": payload.get("candidate_answers", []),
                "recent_turns": payload.get("recent_turns", []),
                "confirmation_already_asked": self._confirmation_already_asked(context),
            },
            ensure_ascii=False,
        )


asr_postprocessor = ASRPostprocessor()
