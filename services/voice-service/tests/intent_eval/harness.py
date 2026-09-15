"""意图判定评测 harness（Path A MVP）。

设计来源：`docs/plans/2026-09-15-intent-accuracy.md`
- 零生产代码改动：本模块只被 `scripts/run_intent_eval.py` 与 `tests/test_intent_eval_gate.py` 使用，不修改 `src/`。
- 一期只评文字样本，不含音频；`asr_confidence` 是注入的固定值（见 `DEFAULT_ASR_CONFIDENCE`）。
- 报告字段 `verdict_source` / `shortcut_hit` / `matched_rule` 现在恒为 LLM 路径的值，
  是为了让规则层（方向 C）落地时**不必重造评测器数据结构**。
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import time
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Iterable, Literal, Sequence

SERVICE_ROOT = Path(__file__).resolve().parents[2]
if str(SERVICE_ROOT) not in sys.path:  # 允许 `python scripts/run_intent_eval.py` 直接 import src.*
    sys.path.insert(0, str(SERVICE_ROOT))

from src.services.asr_postprocess import ASRPostprocessor  # noqa: E402

EVAL_DIR = Path(__file__).resolve().parent
DEFAULT_CASES = EVAL_DIR / "cases.jsonl"
DEFAULT_PENDING = EVAL_DIR / "cases_pending_ruling.jsonl"
DEFAULT_RULINGS = EVAL_DIR / "rulings.jsonl"
DEFAULT_CONTEXTS = EVAL_DIR / "contexts.json"
DEFAULT_BASELINE = EVAL_DIR / "baseline.json"

# MVP 的一期意图标签（规则层落地后扩到含 accept / reject）
INTENT_LABELS: tuple[str, ...] = ("provide", "delegate", "off_topic")

# 一期文字集不携带真实 ASR 置信度：给一个干净音频的固定值，避免把语言概率噪声混进意图评测
DEFAULT_ASR_CONFIDENCE = 0.9

# 门禁默认阈值（对齐计划文档：某桶退步 >2pt 即拒绝；抖动率同口径）
BUCKET_DROP_PT = 2.0
FLIP_RATE_DELTA_PT = 2.0

SCHEMA_VERSION = 1

PROVENANCE_VALUES = ("agent_authored", "human_handwritten", "real_log")

StubMode = Literal["perfect", "off_topic", "delegate", "flaky"]


# ────────────────────────────── 归一化与判分 ──────────────────────────────

def normalize_text(value: Any) -> str:
    """比较用归一化：NFKC → 去空白与标点 → casefold。"""
    text = unicodedata.normalize("NFKC", str(value))
    kept = [
        ch
        for ch in text
        if not ch.isspace() and not unicodedata.category(ch).startswith("P")
    ]
    return "".join(kept).casefold()


def normalize_extracted(value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        return {}
    return {str(k): normalize_text(v) for k, v in value.items()}


def verdict_key(intent: str, extracted: dict[str, Any]) -> str:
    """一次判定的可比较指纹，用于抖动率检测。"""
    normalized = normalize_extracted(extracted)
    return json.dumps(
        {"intent": intent, "extracted": sorted(normalized.items())},
        ensure_ascii=False,
        sort_keys=True,
    )


def grade(case: dict[str, Any], postprocess: dict[str, Any]) -> tuple[bool, list[str]]:
    """判定一次结果是否通过；返回 (passed, reasons)。"""
    reasons: list[str] = []
    expect = case["expect"]
    expected_intent = expect["intent"]
    actual_intent = str(postprocess.get("intent", ""))
    if actual_intent != expected_intent:
        reasons.append(f"intent: 期望 {expected_intent}，实际 {actual_intent}")

    if expect.get("extracted_match", "exact") != "ignore":
        expected_extracted = normalize_extracted(expect.get("extracted", {}))
        actual_extracted = normalize_extracted(postprocess.get("extracted", {}))
        if actual_extracted != expected_extracted:
            reasons.append(
                "extracted: 期望 %s，实际 %s"
                % (
                    json.dumps(expected_extracted, ensure_ascii=False, sort_keys=True),
                    json.dumps(actual_extracted, ensure_ascii=False, sort_keys=True),
                )
            )
    return (not reasons), reasons


# ────────────────────────────── 用例装载 ──────────────────────────────

def load_contexts(path: Path | str = DEFAULT_CONTEXTS) -> dict[str, dict[str, Any]]:
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    return {k: v for k, v in raw.items() if not k.startswith("_")}


def _deep_merge(base: dict[str, Any], patch: dict[str, Any]) -> dict[str, Any]:
    merged = dict(base)
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def resolve_context(case: dict[str, Any], contexts: dict[str, dict[str, Any]]) -> dict[str, Any]:
    ref = case.get("context_ref")
    if not ref:
        raise ValueError(f"用例 {case.get('id')} 缺少 context_ref")
    if ref not in contexts:
        raise ValueError(f"用例 {case.get('id')} 引用了未知 context_ref: {ref}")
    context = contexts[ref]
    patch = case.get("context_patch")
    if patch:
        context = _deep_merge(context, patch)
    # 去掉模板里的说明字段（如 _source），避免污染 ASRPostprocessContext
    return {k: v for k, v in context.items() if not k.startswith("_")}


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for lineno, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        try:
            rows.append(json.loads(stripped))
        except json.JSONDecodeError as exc:
            raise ValueError(f"{path}:{lineno} 不是合法 JSON：{exc}") from exc
    return rows


def load_cases(
    path: Path | str = DEFAULT_CASES,
    contexts_path: Path | str = DEFAULT_CONTEXTS,
    *,
    validate: bool = True,
) -> list[dict[str, Any]]:
    """装载可判分用例（expect 必须非空）。"""
    contexts = load_contexts(contexts_path)
    cases = _read_jsonl(path)
    prepared: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for case in cases:
        case = dict(case)
        case_id = str(case.get("id", ""))
        if validate:
            if not case_id:
                raise ValueError(f"{path}: 存在缺少 id 的用例")
            if case_id in seen_ids:
                raise ValueError(f"{path}: 用例 id 重复：{case_id}")
            seen_ids.add(case_id)
            if not case.get("bucket"):
                raise ValueError(f"用例 {case_id} 缺少 bucket")
            if not isinstance(case.get("expect"), dict) or not case["expect"].get("intent"):
                raise ValueError(f"用例 {case_id} 缺少 expect.intent（需裁定用例请放 cases_pending_ruling.jsonl）")
            if case["expect"]["intent"] not in INTENT_LABELS:
                raise ValueError(f"用例 {case_id} 的 expect.intent 非法：{case['expect']['intent']}")
            provenance = case.get("provenance")
            if provenance and provenance not in PROVENANCE_VALUES:
                raise ValueError(f"用例 {case_id} 的 provenance 非法：{provenance}")
        case["context"] = resolve_context(case, contexts)
        prepared.append(case)
    return prepared


def load_pending_rulings(path: Path | str = DEFAULT_PENDING) -> list[dict[str, Any]]:
    return _read_jsonl(path)


def load_rulings(path: Path | str = DEFAULT_RULINGS) -> list[dict[str, Any]]:
    """已生效的裁定记录。

    裁定不是契约本身：它是"这批用例为什么这么期望"的书面依据，
    契约层面的固化在 ADR 里（见各裁定的 `folds_into`）。
    """
    if not Path(path).exists():
        return []
    return _read_jsonl(path)


def sample_per_bucket(cases: Sequence[dict[str, Any]], per_bucket: int) -> list[dict[str, Any]]:
    """每桶等距抽 N 例（确定性、可复现），用于抖动率抽样。

    等距而非取前 N：用例文件是按桶排块的，取前 N 会只覆盖一个桶。
    """
    if per_bucket <= 0:
        return list(cases)
    by_bucket: dict[str, list[dict[str, Any]]] = {}
    for case in cases:
        by_bucket.setdefault(case["bucket"], []).append(case)
    sampled: list[dict[str, Any]] = []
    for bucket in sorted(by_bucket):
        group = by_bucket[bucket]
        if len(group) <= per_bucket:
            sampled.extend(group)
            continue
        stride = len(group) / per_bucket
        picked = [group[min(len(group) - 1, int(index * stride))] for index in range(per_bucket)]
        sampled.extend(picked)
    order = {case["id"]: index for index, case in enumerate(cases)}
    return sorted(sampled, key=lambda case: order[case["id"]])


# ────────────────────────────── 离线假客户端 ──────────────────────────────

class _StubCompletion:
    def __init__(self, content: str, model: str):
        self.choices = [
            SimpleNamespace(
                message=SimpleNamespace(content=content),
                finish_reason="stop",
            )
        ]
        self._model = model

    def model_dump(self, mode: str = "json") -> dict[str, Any]:
        return {"model": self._model, "choices": [{"finish_reason": "stop"}]}


class _StubCompletions:
    def __init__(self, parent: "StubClient"):
        self._parent = parent

    async def create(self, *, model: str, messages: list[dict[str, str]], **kwargs: Any) -> _StubCompletion:
        self._parent.calls += 1
        payload = self._parent.payload_for(messages)
        return _StubCompletion(json.dumps(payload, ensure_ascii=False), model)


class StubClient:
    """离线假客户端。

    用途：验证 harness / 门禁逻辑本身（离线、零成本），**不是**用来评测模型准确度。
    - perfect：照抄用例期望（门禁应当通过）
    - off_topic：一律判 off_topic（准确率崩，门禁应当失败）
    - delegate：一律判 delegate（同上，且验证委托预期）
    - flaky：每第 3 次调用翻一次结论（用于验证抖动率能被测出来）
    """

    def __init__(self, cases: Sequence[dict[str, Any]], mode: StubMode = "perfect"):
        if mode not in ("perfect", "off_topic", "delegate", "flaky"):
            raise ValueError(f"未知 stub 模式：{mode}")
        self.mode = mode
        self.calls = 0
        self.chat = SimpleNamespace(completions=_StubCompletions(self))
        self._by_text: dict[str, dict[str, Any]] = {}
        for case in cases:
            self._by_text.setdefault(normalize_text(case["raw_text"]), case)

    def _payload(self, intent: str, extracted: dict[str, Any], confidence: float = 0.9) -> dict[str, Any]:
        return {
            "corrected_text": "",
            "correction_applied": False,
            "correction_reason": None,
            "extracted": extracted,
            "intent_matched": intent == "provide",
            "intent": intent,
            "guidance": {"npc_line": None},
            "confidence": confidence,
        }

    def payload_for(self, messages: list[dict[str, str]]) -> dict[str, Any]:
        user = json.loads(messages[-1]["content"])
        raw_text = str(user.get("raw_text", ""))
        if self.mode == "off_topic":
            payload = self._payload("off_topic", {})
        elif self.mode == "delegate":
            payload = self._payload("delegate", {})
        elif self.mode == "flaky" and self.calls % 3 == 0:
            payload = self._payload("off_topic", {})
        else:
            case = self._by_text.get(normalize_text(raw_text))
            expect = case["expect"] if case else {"intent": "off_topic", "extracted": {}}
            payload = self._payload(expect["intent"], expect.get("extracted", {}))
        payload["corrected_text"] = raw_text
        return payload


def ensure_stub_env() -> None:
    """离线模式仍需通过 post-processor 的 api_key 闸门；用占位值，不发网络请求。

    同时强制打开 ASR_POSTPROCESS_ENABLED：否则外部环境若把它设成 false，
    stub 会走 disabled 降级路径，harness 自检就测不到该测的东西。
    """
    os.environ.setdefault("ASR_POSTPROCESS_API_KEY", "stub-key")
    os.environ["ASR_POSTPROCESS_ENABLED"] = "true"


# ────────────────────────────── 评测执行 ──────────────────────────────

@dataclass
class CaseResult:
    case_id: str
    bucket: str
    raw_text: str
    expected_intent: str
    expected_extracted: dict[str, Any]
    actual_intent: str
    actual_extracted: dict[str, Any]
    pass_rate: float
    passed_first: bool
    reasons: list[str]
    applied: bool
    applied_repeats: int
    fallback_repeats: int
    fallback_reason: str | None
    verdict_source: str | None
    shortcut_hit: bool
    matched_rule: str | None
    latency_ms: int
    verdicts: list[str] = field(default_factory=list)

    @property
    def flipped(self) -> bool:
        return len(set(self.verdicts)) > 1

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.case_id,
            "bucket": self.bucket,
            "raw_text": self.raw_text,
            "expect": {"intent": self.expected_intent, "extracted": self.expected_extracted},
            "actual": {"intent": self.actual_intent, "extracted": self.actual_extracted},
            "pass_rate": round(self.pass_rate, 4),
            "pass": self.passed_first,
            "reasons": self.reasons,
            "applied": self.applied,
            "applied_repeats": self.applied_repeats,
            "fallback_repeats": self.fallback_repeats,
            "fallback_reason": self.fallback_reason,
            "verdict_source": self.verdict_source,
            "shortcut_hit": self.shortcut_hit,
            "matched_rule": self.matched_rule,
            "latency_ms": self.latency_ms,
            "flipped": self.flipped,
        }


def _verdict_source(postprocess: dict[str, Any]) -> str | None:
    """规则层上线前：短路恒为未命中，判决来源恒为 llm；fallback 不是判决，返回 None。"""
    if not postprocess.get("applied"):
        return None
    return "rule" if postprocess.get("shortcut_hit") else "llm"


async def run_case(
    case: dict[str, Any],
    postprocessor: ASRPostprocessor,
    *,
    repeats: int = 1,
) -> CaseResult:
    outcomes: list[dict[str, Any]] = []
    latencies: list[int] = []
    for _ in range(repeats):
        started = time.monotonic()
        result = await postprocessor.process(
            text=case["raw_text"],
            asr_confidence=case.get("asr_confidence", DEFAULT_ASR_CONFIDENCE),
            language=case["context"].get("language") or "zh",
            context=case["context"],
        )
        latencies.append(int((time.monotonic() - started) * 1000))
        outcomes.append(result)

    passes: list[bool] = []
    reasons_first: list[str] = []
    for index, outcome in enumerate(outcomes):
        passed, reasons = grade(case, outcome)
        passes.append(passed)
        if index == 0:
            reasons_first = reasons

    first = outcomes[0]
    return CaseResult(
        case_id=case["id"],
        bucket=case["bucket"],
        raw_text=case["raw_text"],
        expected_intent=case["expect"]["intent"],
        expected_extracted=case["expect"].get("extracted", {}),
        actual_intent=str(first.get("intent", "")),
        actual_extracted=first.get("extracted", {}) or {},
        pass_rate=sum(passes) / len(passes),
        passed_first=passes[0],
        reasons=reasons_first,
        applied=bool(first.get("applied")),
        applied_repeats=sum(1 for o in outcomes if o.get("applied")),
        fallback_repeats=sum(1 for o in outcomes if not o.get("applied")),
        fallback_reason=first.get("fallback_reason"),
        verdict_source=_verdict_source(first),
        shortcut_hit=bool(first.get("shortcut_hit")),
        matched_rule=first.get("matched_rule"),
        latency_ms=max(latencies) if latencies else 0,
        verdicts=[verdict_key(str(o.get("intent", "")), o.get("extracted", {}) or {}) for o in outcomes],
    )


async def run_eval(
    cases: Sequence[dict[str, Any]],
    postprocessor: ASRPostprocessor,
    *,
    repeats: int = 1,
    concurrency: int = 4,
    progress: bool = False,
) -> list[CaseResult]:
    semaphore = asyncio.Semaphore(max(1, concurrency))
    done = 0
    total = len(cases)
    lock = asyncio.Lock()

    async def worker(case: dict[str, Any]) -> CaseResult:
        nonlocal done
        async with semaphore:
            result = await run_case(case, postprocessor, repeats=repeats)
        if progress:
            async with lock:
                done += 1
                mark = "ok " if result.passed_first else "FAIL"
                print(f"  [{done:>3}/{total}] {mark} {result.case_id} {result.raw_text[:24]}", flush=True)
        return result

    return list(await asyncio.gather(*(worker(case) for case in cases)))


# ────────────────────────────── 指标与门禁 ──────────────────────────────

def confusion_matrix(results: Sequence[CaseResult]) -> dict[str, dict[str, int]]:
    """expected × actual。含一期不会出现的标签，便于规则层扩 accept/reject 后直接复用。"""
    labels = list(INTENT_LABELS) + ["accept", "reject", "other"]
    matrix = {expected: {actual: 0 for actual in labels} for expected in labels}
    for result in results:
        expected = result.expected_intent if result.expected_intent in labels else "other"
        actual = result.actual_intent if result.actual_intent in labels else "other"
        matrix[expected][actual] += 1
    return {k: {a: n for a, n in v.items() if n} for k, v in matrix.items() if any(v.values())}


def compute_metrics(
    results: Sequence[CaseResult],
    *,
    repeats: int,
    mode: str,
    model: str | None,
    partial: bool = False,
    durations_ms: int | None = None,
) -> dict[str, Any]:
    buckets: dict[str, dict[str, Any]] = {}
    for result in results:
        entry = buckets.setdefault(result.bucket, {"n": 0, "pass_sum": 0.0, "cases": []})
        entry["n"] += 1
        entry["pass_sum"] += result.pass_rate
        entry["cases"].append(result.case_id)

    bucket_metrics: dict[str, dict[str, Any]] = {}
    for name, entry in sorted(buckets.items()):
        accuracy = entry["pass_sum"] / entry["n"] if entry["n"] else 0.0
        bucket_metrics[name] = {
            "n": entry["n"],
            "accuracy": round(accuracy, 4),
        }

    min_bucket = None
    if bucket_metrics:
        worst = min(bucket_metrics.items(), key=lambda kv: (kv[1]["accuracy"], kv[0]))
        min_bucket = {"bucket": worst[0], "accuracy": worst[1]["accuracy"]}

    flips = [r for r in results if r.flipped]
    flip_rate = (len(flips) / len(results)) if (results and repeats > 1) else None

    return {
        "schema_version": SCHEMA_VERSION,
        "mode": mode,
        "model": model,
        "repeats": repeats,
        "partial": partial,
        "cases": len(results),
        "overall_accuracy": round(
            (sum(r.pass_rate for r in results) / len(results)) if results else 0.0, 4
        ),
        "buckets": bucket_metrics,
        "min_bucket": min_bucket,
        "flip_rate": round(flip_rate, 4) if flip_rate is not None else None,
        "flipped_cases": sorted(r.case_id for r in flips),
        "fallback_count": sum(r.fallback_repeats for r in results),
        "fallback_reasons": sorted({r.fallback_reason for r in results if r.fallback_reason}),
        "shortcut_hits": sum(1 for r in results if r.shortcut_hit),
        "verdict_sources": sorted({r.verdict_source for r in results if r.verdict_source}),
        "llm_calls_lower_bound": sum(r.applied_repeats for r in results),
        "max_latency_ms": max((r.latency_ms for r in results), default=0),
        "duration_ms": durations_ms,
        "confusion": confusion_matrix(results),
        "thresholds": {
            "bucket_drop_pt": BUCKET_DROP_PT,
            "flip_rate_delta_pt": FLIP_RATE_DELTA_PT,
        },
    }


@dataclass
class GateReport:
    passed: bool
    failures: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def check_gate(
    run: dict[str, Any],
    baseline: dict[str, Any] | None,
    *,
    bucket_drop_pt: float = BUCKET_DROP_PT,
    flip_delta_pt: float = FLIP_RATE_DELTA_PT,
) -> GateReport:
    failures: list[str] = []
    notes: list[str] = []

    if not baseline:
        notes.append("无基线：本次结果可作为基线（--update-baseline），门禁未生效")
        return GateReport(passed=True, failures=failures, notes=notes)

    baseline_mode = baseline.get("mode")
    if baseline_mode != run.get("mode"):
        failures.append(
            f"基线模式不匹配：基线 mode={baseline_mode}，本次 mode={run.get('mode')}"
            "（stub 基线与 live 结果不可互相门禁）"
        )
        return GateReport(passed=False, failures=failures, notes=notes)

    threshold = float(baseline.get("thresholds", {}).get("bucket_drop_pt", bucket_drop_pt))
    run_buckets = run.get("buckets", {})
    base_buckets = baseline.get("buckets", {})

    for name, base in sorted(base_buckets.items()):
        current = run_buckets.get(name)
        if current is None:
            if run.get("partial"):
                notes.append(f"桶 {name} 本次被过滤跳过（partial 运行不参与棘轮）")
            else:
                failures.append(f"桶 {name} 在本次运行中缺失（覆盖被删除，棘轮不允许）")
            continue
        drop_pt = (base["accuracy"] - current["accuracy"]) * 100
        if drop_pt > threshold:
            failures.append(
                f"桶 {name} 退步 {drop_pt:.1f}pt（基线 {base['accuracy']:.3f} → 本次 {current['accuracy']:.3f}，阈值 {threshold:.1f}pt）"
            )

    for name in sorted(set(run_buckets) - set(base_buckets)):
        notes.append(f"新桶 {name}（基线中不存在，本次不计退步）")

    flip_threshold = float(baseline.get("thresholds", {}).get("flip_rate_delta_pt", flip_delta_pt))
    if run.get("repeats", 1) <= 1:
        notes.append("抖动率门禁跳过（repeats=1；按计划只在 nightly/slow 通道跑 N=5）")
    elif run.get("flip_rate") is None:
        notes.append("抖动率缺失，门禁跳过")
    elif baseline.get("flip_rate") is None:
        notes.append(f"基线无抖动率，本次记录为 {run['flip_rate']:.3f}（下次起可门禁）")
    else:
        delta_pt = (run["flip_rate"] - baseline["flip_rate"]) * 100
        if delta_pt > flip_threshold:
            failures.append(
                f"抖动率上升 {delta_pt:.1f}pt（基线 {baseline['flip_rate']:.3f} → 本次 {run['flip_rate']:.3f}，阈值 {flip_threshold:.1f}pt）"
            )

    return GateReport(passed=not failures, failures=failures, notes=notes)


def baseline_from_metrics(metrics: dict[str, Any], *, note: str | None = None) -> dict[str, Any]:
    baseline = {
        "schema_version": SCHEMA_VERSION,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "mode": metrics.get("mode"),
        "model": metrics.get("model"),
        "repeats": metrics.get("repeats"),
        "buckets": {
            name: {"n": data["n"], "accuracy": data["accuracy"]}
            for name, data in metrics.get("buckets", {}).items()
        },
        "min_bucket": metrics.get("min_bucket"),
        "overall_accuracy": metrics.get("overall_accuracy"),
        "flip_rate": metrics.get("flip_rate"),
        "thresholds": {
            "bucket_drop_pt": BUCKET_DROP_PT,
            "flip_rate_delta_pt": FLIP_RATE_DELTA_PT,
        },
    }
    if note:
        baseline["note"] = note
    return baseline


def build_postprocessor(*, stub: StubMode | None, cases: Sequence[dict[str, Any]]) -> ASRPostprocessor:
    if stub:
        ensure_stub_env()
        return ASRPostprocessor(client=StubClient(cases, mode=stub))  # type: ignore[arg-type]
    return ASRPostprocessor()
