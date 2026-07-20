import json
import logging
import os
import re
import time
from typing import Any, Literal

import openai
from pydantic import BaseModel, ConfigDict, Field, ValidationError


logger = logging.getLogger(__name__)


FallbackReason = Literal[
    "disabled",
    "missing_context",
    "missing_api_key",
    "timeout",
    "provider_error",
    "invalid_json",
    "schema_error",
]


class ExpectedSlot(BaseModel):
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


class ASRGuidanceOutput(BaseModel):
    npc_line: str | None = None


class LLMPostprocessOutput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    corrected_text: str
    correction_applied: bool
    correction_reason: str | None
    extracted: dict[str, str | int | float | bool | None] = Field(default_factory=dict)
    intent_matched: bool = True
    guidance: ASRGuidanceOutput = Field(default_factory=ASRGuidanceOutput)
    confidence: float = Field(ge=0.0, le=1.0)


class ASRPostprocessResult(BaseModel):
    applied: bool
    corrected_text: str
    correction_reason: str | None
    extracted: dict[str, str | int | float | bool | None]
    intent_matched: bool
    guidance: ASRGuidanceOutput
    confidence: float
    fallback_reason: FallbackReason | None
    model: str | None
    latency_ms: int


class ASRPostprocessor:
    def __init__(self, client: openai.AsyncOpenAI | None = None):
        self.client = client

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

        if not parsed_context.npc_question or len(parsed_context.expected_slots) == 0:
            logger.info(
                "[ASR-POSTPROCESS] fallback reason=missing_context detail=incomplete_context npc_question_present=%s expected_slot_count=%s text_len=%s",
                bool(parsed_context.npc_question),
                len(parsed_context.expected_slots),
                len(text),
            )
            return self._fallback(text, "missing_context")

        api_key = os.environ.get("ASR_POSTPROCESS_API_KEY") or os.environ.get("OPENAI_API_KEY")
        if not api_key:
            logger.info("[ASR-POSTPROCESS] fallback reason=missing_api_key text_len=%s", len(text))
            return self._fallback(text, "missing_api_key")

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
        timeout_ms = int(os.environ.get("ASR_POSTPROCESS_TIMEOUT_MS", "30000"))
        max_tokens = int(os.environ.get("ASR_POSTPROCESS_MAX_TOKENS", "800"))
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
            llm_payload = await self._call_llm(
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
                "[ASR-POSTPROCESS] provider timeout base_url=%s model=%s timeout_ms=%s",
                base_url,
                model,
                timeout_ms,
            )
            return self._fallback(text, "timeout", latency_ms=timeout_ms)
        except openai.APIStatusError as exc:
            message = getattr(exc, "message", str(exc))[:500]
            logger.warning(
                "[ASR-POSTPROCESS] provider api_status_error base_url=%s model=%s status_code=%s message=%r",
                base_url,
                model,
                getattr(exc, "status_code", None),
                message,
            )
            return self._fallback(text, "provider_error", latency_ms=self._elapsed_ms(started))
        except openai.APIError as exc:
            message = getattr(exc, "message", str(exc))[:500]
            logger.warning(
                "[ASR-POSTPROCESS] provider api_error base_url=%s model=%s error_type=%s message=%r",
                base_url,
                model,
                exc.__class__.__name__,
                message,
            )
            return self._fallback(text, "provider_error", latency_ms=self._elapsed_ms(started))
        except RuntimeError as exc:
            logger.warning(
                "[ASR-POSTPROCESS] provider runtime_error model=%s error=%s",
                model,
                str(exc),
            )
            return self._fallback(text, "provider_error", latency_ms=self._elapsed_ms(started))

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

        extracted = self._filter_extracted(output.extracted, parsed_context)
        guidance = self._filter_guidance(output.guidance, parsed_context)
        logger.info(
            "[ASR-POSTPROCESS] extracted raw_keys=%s filtered_keys=%s allowed_keys=%s",
            sorted(output.extracted.keys()),
            sorted(extracted.keys()),
            [slot.key for slot in parsed_context.expected_slots],
        )
        result = ASRPostprocessResult(
            applied=True,
            corrected_text=output.corrected_text,
            correction_reason=output.correction_reason,
            extracted=extracted,
            intent_matched=output.intent_matched,
            guidance=guidance,
            confidence=output.confidence,
            fallback_reason=None,
            model=model,
            latency_ms=self._elapsed_ms(started),
        )
        dumped = result.model_dump()
        logger.info(
            "[ASR-POSTPROCESS] success corrected_text_len=%s correction_applied=%s correction_reason_present=%s intent_matched=%s guidance_present=%s confidence=%.4f latency_ms=%s model=%s",
            len(dumped["corrected_text"]),
            output.correction_applied,
            bool(dumped["correction_reason"]),
            dumped["intent_matched"],
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
        client = self.client or openai.AsyncOpenAI(
            api_key=api_key,
            base_url=base_url,
            timeout=timeout_ms / 1000,
        )
        should_close = self.client is None
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

        try:
            completion = await client.chat.completions.create(
                model=model,
                messages=messages,
                response_format={"type": "json_object"},
                temperature=0.1,
                max_tokens=max_tokens,
            )
            content = completion.choices[0].message.content if completion.choices else None
            raw_completion = completion.model_dump(mode="json")
            logger.info(
                "[ASR-POSTPROCESS] llm raw_completion=%s",
                json.dumps(raw_completion, ensure_ascii=False, default=str),
            )
            logger.info(
                "[ASR-POSTPROCESS] llm raw_response_present=%s raw_response_len=%s",
                isinstance(content, str) and bool(content),
                len(content) if isinstance(content, str) else 0,
            )
            if not isinstance(content, str) or not content:
                local_payload = self._local_empty_content_fallback(text, context)
                if local_payload:
                    logger.info("[ASR-POSTPROCESS] llm empty content recovered locally")
                    return local_payload
                raise RuntimeError("Empty LLM response")
            return content
        finally:
            if should_close:
                await client.close()

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

    def _fallback(self, text: str, reason: FallbackReason, latency_ms: int = 0) -> dict[str, Any]:
        return ASRPostprocessResult(
            applied=False,
            corrected_text=text,
            correction_reason=None,
            extracted={},
            intent_matched=True,
            guidance=ASRGuidanceOutput(),
            confidence=0.0,
            fallback_reason=reason,
            model=None,
            latency_ms=latency_ms,
        ).model_dump()

    def _elapsed_ms(self, started: float) -> int:
        return int((time.monotonic() - started) * 1000)

    def _system_prompt(self) -> str:
        return (
            "You are an ASR post-processor for a children's language-learning RPG. "
            "Return one JSON object only. No reasoning. No markdown. "
            "Required keys: corrected_text, correction_applied, correction_reason, extracted, intent_matched, guidance, confidence. "
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
