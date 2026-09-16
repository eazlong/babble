"""意图判定评测门禁的离线测试。

这些用例验证的是 **harness 与门禁逻辑本身**（离线、零成本），不是模型准确度：
- perfect stub 必须通过门禁；
- 退化的 stub 必须以**指名到桶**的方式失败；
- 抖动率必须能被测出来；
- 基线与本次运行的模式不匹配时必须拒绝比较。

真实模型的评测在 `test_live_baseline_gate`（需 INTENT_EVAL_LIVE=1，会花钱）。
"""

from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
from types import SimpleNamespace

import pytest

from tests.intent_eval.harness import (
    INTENT_LABELS,
    _verdict_source,
    baseline_from_metrics,
    build_postprocessor,
    check_gate,
    compute_metrics,
    grade,
    load_cases,
    load_pending_rulings,
    load_rulings,
    normalize_text,
    run_eval,
    sample_per_bucket,
    DEFAULT_BASELINE,
)

EVAL_DIR = Path(__file__).resolve().parent / "intent_eval"


def _run_stub(mode: str, *, repeats: int = 1, cases=None, mode_label: str | None = None) -> dict:
    cases = cases if cases is not None else load_cases()
    postprocessor = build_postprocessor(stub=mode, cases=cases)
    results = asyncio.run(run_eval(cases, postprocessor, repeats=repeats, concurrency=8))
    return compute_metrics(results, repeats=repeats, mode=mode_label or f"stub:{mode}", model="stub")


# ────────────────────────────── 用例集本身 ──────────────────────────────

def test_cases_are_wellformed_and_cover_mvp_buckets() -> None:
    cases = load_cases()
    assert len(cases) >= 60, "MVP 要求两个桶合计 60–80 例"
    buckets = {c["bucket"] for c in cases}
    assert buckets == {"closed_set", "negative"}, f"MVP 只覆盖两个桶，实际 {buckets}"
    ids = [c["id"] for c in cases]
    assert len(ids) == len(set(ids)), "用例 id 必须唯一"
    for case in cases:
        assert case["expect"]["intent"] in INTENT_LABELS
        assert case["context"]["expected_slots"], f"{case['id']} 的上下文缺少 expected_slots"
        assert case["raw_text"].strip()
    closed = [c for c in cases if c["bucket"] == "closed_set"]
    assert any(c["expect"]["intent"] == "provide" for c in closed)
    assert any(c["expect"]["intent"] == "off_topic" for c in closed), "封闭题桶必须含近义误命中"


def test_every_case_has_a_note_and_provenance() -> None:
    """P4：每条样本要能说明它钉住什么；provenance 让『偏差』可见而不是被掩盖。"""
    for case in load_cases():
        assert case.get("note"), f"{case['id']} 缺少 note"
        assert case.get("provenance"), f"{case['id']} 缺少 provenance"


def test_pending_rulings_are_not_graded() -> None:
    pending = load_pending_rulings()
    assert pending, "待裁定用例文件为空，说明边界裁定被悄悄塞进了评测集"
    for case in pending:
        assert case.get("expect") is None
        assert case.get("ruling_question"), f"{case['id']} 必须写清待裁定的问题"
    graded_ids = {c["id"] for c in load_cases()}
    assert not (graded_ids & {c["id"] for c in pending}), "待裁定用例不得同时出现在可判分集里"


def test_rulings_are_recorded_and_consistent() -> None:
    """裁定必须留下书面依据，且**生效后要从不裁定集里移除**——否则裁定等于没做。"""
    rulings = load_rulings()
    assert rulings, "rulings.jsonl 为空：裁定过程没有留痕"
    graded = {case["id"] for case in load_cases()}
    pending = {case["id"] for case in load_pending_rulings()}
    # 被后续裁定取代的用例 id（已从待裁定集移除）也应被引用得到
    superseded_ids = {r["supersedes"] for r in rulings if r.get("supersedes")}
    known_cases = graded | pending | superseded_ids
    seen: set[str] = set()

    for ruling in rulings:
        ruling_id = ruling["id"]
        assert ruling_id not in seen, f"裁定 id 重复：{ruling_id}"
        seen.add(ruling_id)
        for field_name in ("decided_at", "title", "decision", "rationale", "affects_cases"):
            assert ruling.get(field_name), f"{ruling_id} 缺少 {field_name}"
        assert isinstance(ruling["rationale"], list) and ruling["rationale"], (
            f"{ruling_id} 的 rationale 必须是非空列表（裁定要有依据）"
        )
        superseded = ruling.get("supersedes")
        if superseded:
            assert superseded not in pending, f"{superseded} 已裁定却仍在待裁定集里"
        for case_id in ruling["affects_cases"]:
            assert case_id in known_cases, (
                f"{ruling_id} 引用了不存在的用例 {case_id}"
            )


def test_closed_set_expectations_are_canonical_candidates() -> None:
    """rule_001 的可执行形式：封闭题的期望 extracted 必须是候选规范值，而不是玩家原话。

    这条不变量能挡住未来写用例时把原话（如『接着走』）当成期望值——
    那会让门禁去要求一个已经裁定为错误的行为。
    """
    violations: list[str] = []
    for case in load_cases():
        candidates = case["context"].get("candidate_answers") or []
        if not candidates or case["expect"]["intent"] != "provide":
            continue
        normalized_candidates = {normalize_text(candidate) for candidate in candidates}
        for key, value in case["expect"].get("extracted", {}).items():
            if normalize_text(value) not in normalized_candidates:
                violations.append(f"{case['id']}[{key}] = {value!r} 不在候选表内")
    assert not violations, violations


def test_free_slot_exception_is_documented_where_it_matters() -> None:
    """涉及值池的裁定必须写明自由槽例外。

    刻意**不**做"期望值不得等于池成员"这类静态断言：孩子真说了池里的名字
    与"被改写成池成员"在静态上无法区分，那种断言将来必然误判。
    这里只保证例外被写下来（执行层面靠 prompt/规则层设计，见 rule_001）。
    """
    for ruling in load_rulings():
        text = f"{ruling.get('title', '')} {ruling.get('decision', '')}"
        if "值池" in text:
            assert ruling.get("exception"), (
                f"{ruling['id']} 涉及值池却未写明例外（自由槽不得改写为池成员）"
            )


def test_stub_is_context_aware_for_identical_utterances() -> None:
    """两条用例可以同原话、只差问句（cs_040 vs cs_041）——stub 也必须按上下文取期望值。"""
    shared = [case for case in load_cases() if case["raw_text"] == "My name is Lily, nice to meet you"]
    assert len(shared) == 2, "cs_040/cs_041 这对同句不同问句的用例应同时存在"
    questions = {case["context"]["npc_question"] for case in shared}
    assert len(questions) == 2, "两条用例的问句必须不同，否则这条不变量无意义"

    metrics = _run_stub("perfect")
    assert metrics["overall_accuracy"] == 1.0, "perfect stub 在同句不同问句时取错了期望值"


def test_single_run_tolerates_one_noisy_case_but_not_two() -> None:
    """N=1 时一例退步算噪声（一例在 27 例桶里就是 3.7pt），两例才算回归。

    2pt 阈值本是给 nightly N=5 设计的（pass_rate 按次平均）；单次跑直接用会让任何
    一个已知不稳定用例（cs_040 / neg_017）把门禁打红，团队随后就会开始"顺手更新基线"。
    """
    from src.services.asr_postprocess import ASRPostprocessor

    def run_with_failures(failing: int) -> dict:
        # 每例必须用不同的 raw_text：否则"让前 N 例失败"的选择器会把所有例子都命中
        cases = [_mixed_case(f"mx_{index}", f"Nice to meet you {index}") for index in range(28)]
        bad_texts = {case["raw_text"] for case in cases[:failing]}

        class _Degrading(_MixedCompletions):
            async def create(self, *, model: str, messages: list[dict], **kwargs) -> object:
                raw = str(json.loads(messages[-1]["content"]).get("raw_text", ""))
                if raw in bad_texts:
                    self.calls += 1
                    return SimpleNamespace(
                        choices=[
                            SimpleNamespace(
                                message=SimpleNamespace(
                                    content=json.dumps(
                                        {
                                            "corrected_text": raw,
                                            "correction_applied": False,
                                            "correction_reason": None,
                                            "extracted": {},
                                            "intent_matched": False,
                                            "intent": "off_topic",
                                            "guidance": {"npc_line": None},
                                            "confidence": 0.9,
                                        },
                                        ensure_ascii=False,
                                    )
                                ),
                                finish_reason="stop",
                            )
                        ],
                        model_dump=lambda mode="json": {"model": "degrading"},
                    )
                return await super().create(model=model, messages=messages, **kwargs)

        postprocessor = ASRPostprocessor(
            client=SimpleNamespace(chat=SimpleNamespace(completions=_Degrading(set())))  # type: ignore[arg-type]
        )
        results = asyncio.run(run_eval(cases, postprocessor, repeats=1, concurrency=1))
        return compute_metrics(results, repeats=1, mode="live", model="degrading")

    baseline = baseline_from_metrics(run_with_failures(0))

    one_noisy = run_with_failures(1)
    gate_one = check_gate(one_noisy, baseline)
    assert gate_one.passed, f"单例退步被当成回归：{gate_one.failures}"

    two_regressed = run_with_failures(2)
    gate_two = check_gate(two_regressed, baseline)
    assert not gate_two.passed, "两例退步应当判为回归"


def test_sample_per_bucket_is_stratified_and_deterministic() -> None:
    """抖动率抽样必须等距覆盖每个桶——用例文件按桶排块，取前 N 会只覆盖一个桶。"""
    cases = load_cases()
    sampled = sample_per_bucket(cases, 5)
    assert len(sampled) == 10
    counts: dict[str, int] = {}
    for case in sampled:
        counts[case["bucket"]] = counts.get(case["bucket"], 0) + 1
    assert counts == {"closed_set": 5, "negative": 5}, counts
    assert sample_per_bucket(cases, 5) == sampled, "抽样必须确定性可复现"
    head = {c["id"] for c in cases[:10]}
    assert {c["id"] for c in sampled} != head, "抽样退化成取前 N 会漏掉整个 negative 桶"
    assert sample_per_bucket(cases, 0) == list(cases)


# ────────────────────────────── 归一化与判分 ──────────────────────────────

@pytest.mark.parametrize(
    "left,right",
    [
        ("Nice to meet you!", "nice to meet you"),
        ("出发！", "出发"),
        ("Ｌｅｔ＇ｓ　ｇｏ", "let's go"),
        ("I am fine, thank you", "i am fine thank you"),
    ],
)
def test_normalize_text_is_punctuation_and_case_insensitive(left: str, right: str) -> None:
    assert normalize_text(left) == normalize_text(right)


def test_grade_reports_both_intent_and_extracted_mismatch() -> None:
    case = {
        "id": "x",
        "expect": {"intent": "provide", "extracted": {"answer": "出发"}},
    }
    passed, reasons = grade(case, {"intent": "off_topic", "extracted": {}})
    assert not passed
    assert len(reasons) == 2, reasons


def test_grade_can_ignore_extracted_when_case_says_so() -> None:
    case = {"id": "x", "expect": {"intent": "provide", "extracted": {"answer": "出发"}, "extracted_match": "ignore"}}
    passed, reasons = grade(case, {"intent": "provide", "extracted": {"answer": "别的"}})
    assert passed, reasons


# ────────────────────────────── 门禁逻辑 ──────────────────────────────

def test_perfect_stub_passes_against_perfect_baseline() -> None:
    metrics = _run_stub("perfect")
    assert metrics["overall_accuracy"] == 1.0, "perfect stub 应全对；否则是用例或 harness 有问题"
    baseline = baseline_from_metrics(metrics)
    gate = check_gate(metrics, baseline)
    assert gate.passed, gate.failures


def test_degraded_stub_fails_gate_naming_the_bucket() -> None:
    good = baseline_from_metrics(_run_stub("perfect"))
    # 刻意共用 mode 标签：本用例要隔离验证的是「桶退步」这条，而不是模式不匹配那条
    bad = _run_stub("delegate", mode_label="stub:perfect")  # 一律 delegate：没有任何用例期望它
    assert bad["overall_accuracy"] == 0.0
    gate = check_gate(bad, good)
    assert not gate.passed
    joined = " ".join(gate.failures)
    assert "negative" in joined and "closed_set" in joined, gate.failures


def test_degenerate_strategy_can_ace_one_bucket_which_is_why_gates_are_per_bucket() -> None:
    """『一律判 off_topic』的退化策略能拿满 negative 桶，却在 closed_set 上崩掉。

    这正是门禁必须看**每个桶**（而非总体准确率）的原因：总体 0.66 看起来还行。
    """
    good = baseline_from_metrics(_run_stub("perfect"))
    bad = _run_stub("off_topic", mode_label="stub:perfect")
    assert bad["buckets"]["negative"]["accuracy"] == 1.0
    assert bad["buckets"]["closed_set"]["accuracy"] < 0.5
    gate = check_gate(bad, good)
    assert not gate.passed
    assert any("closed_set" in item for item in gate.failures), gate.failures
    assert not any("negative" in item for item in gate.failures), gate.failures


def test_small_regression_within_threshold_is_not_a_failure() -> None:
    """棘轮是 2pt 容差，不是零容忍——否则正常迭代会被噪声卡死。"""
    metrics = _run_stub("perfect")
    baseline = baseline_from_metrics(metrics)
    baseline["buckets"]["negative"]["accuracy"] = metrics["buckets"]["negative"]["accuracy"] - 0.01
    gate = check_gate(metrics, baseline)
    assert gate.passed, gate.failures


def test_flip_rate_is_measured_and_gated() -> None:
    # 基线与本次运行必须同为 stub:flaky 才能比较抖动率（模式不匹配会被门禁直接拒绝）
    baseline_metrics = _run_stub("perfect", repeats=3, mode_label="stub:flaky")
    assert baseline_metrics["flip_rate"] == 0.0, "perfect stub 不应抖动"
    baseline = baseline_from_metrics(baseline_metrics)

    flaky_metrics = _run_stub("flaky", repeats=3)
    assert flaky_metrics["flip_rate"] and flaky_metrics["flip_rate"] > 0, "flaky stub 必须被测出抖动"
    assert flaky_metrics["flipped_cases"], "抖动用例清单不应为空"

    gate = check_gate(flaky_metrics, baseline)
    assert not gate.passed
    assert any("抖动率" in item for item in gate.failures), gate.failures


def test_flip_gate_is_skipped_when_repeats_is_one() -> None:
    baseline = baseline_from_metrics(_run_stub("perfect", repeats=3))
    single = _run_stub("perfect", repeats=1)
    assert single["flip_rate"] is None
    gate = check_gate(single, baseline)
    assert gate.passed
    assert any("抖动率门禁跳过" in note for note in gate.notes), gate.notes


def test_baseline_mode_mismatch_is_rejected() -> None:
    stub_metrics = _run_stub("perfect")
    stub_baseline = baseline_from_metrics(stub_metrics)
    live_like = dict(stub_metrics)
    live_like["mode"] = "live"
    gate = check_gate(live_like, stub_baseline)
    assert not gate.passed
    assert any("模式不匹配" in item for item in gate.failures), gate.failures


def test_removed_bucket_fails_but_partial_run_only_notes() -> None:
    good = baseline_from_metrics(_run_stub("perfect"))
    cases = [c for c in load_cases() if c["bucket"] == "closed_set"]
    partial = _run_stub("perfect", cases=cases)
    partial["partial"] = True

    gate_partial = check_gate(partial, good)
    assert gate_partial.passed, gate_partial.failures
    assert any("被过滤跳过" in note for note in gate_partial.notes), gate_partial.notes

    partial["partial"] = False
    gate_silent = check_gate(partial, good)
    assert not gate_silent.passed
    assert any("覆盖被删除" in item for item in gate_silent.failures), gate_silent.failures


def test_no_baseline_is_a_note_not_a_failure() -> None:
    gate = check_gate(_run_stub("perfect"), None)
    assert gate.passed
    assert any("无基线" in note for note in gate.notes), gate.notes


def test_stub_client_counts_calls() -> None:
    cases = load_cases()[:5]
    postprocessor = build_postprocessor(stub="perfect", cases=cases)
    results = asyncio.run(run_eval(cases, postprocessor, repeats=1, concurrency=1))
    assert len(results) == 5
    assert all(r.applied for r in results)


def test_call_accounting_counts_repeats_not_cases() -> None:
    """费用记账要按『次』而不是按『例』——N=5 的一次全量跑是 5 倍用例数的调用。"""
    total_cases = len(load_cases())
    metrics = _run_stub("perfect", repeats=3)
    assert metrics["cases"] == total_cases
    assert metrics["llm_calls_lower_bound"] == total_cases * 3
    assert metrics["fallback_count"] == 0


def test_reserved_fields_keep_rule_layer_semantics() -> None:
    """为规则层（方向 C）预留的字段语义：降级不是判决，短路判决来源为 rule。"""
    assert _verdict_source({"applied": False, "fallback_reason": "missing_context"}) is None
    assert _verdict_source({"applied": True}) == "llm"
    assert _verdict_source({"applied": True, "shortcut_hit": True}) == "rule"
    metrics = _run_stub("perfect")
    assert metrics["shortcut_hits"] == 0, "规则层尚未落地，短路命中必须为 0"
    assert metrics["verdict_sources"] == ["llm"]


# ────────────────────── 测量有效性：降级不得污染准确率 ──────────────────────

_FALLBACK_CONTEXT = {
    "npc_question": "请跟老师读：Nice to meet you",
    "expected_slots": [{"key": "answer", "type": "keyword", "description": "课堂回答"}],
    "expected_answer_type": "keyword",
    "candidate_answers": ["Nice to meet you"],
    "recent_turns": [],
    "language": "en",
    "task_mode": "dialogue",
}


def _mixed_case(case_id: str, raw_text: str) -> dict:
    return {
        "id": case_id,
        "bucket": "closed_set",
        "raw_text": raw_text,
        "expect": {"intent": "provide", "extracted": {"answer": "Nice to meet you"}},
        "context": _FALLBACK_CONTEXT,
    }


class _MixedCompletions:
    """按 raw_text 决定这次调用是"正常判决"还是"网关返回 HTML"（即 provider 降级）。"""

    def __init__(self, fallback_texts: set[str], *, fallback_once: bool = False):
        self._fallback_texts = fallback_texts
        self._fallback_once = fallback_once
        self._already_fell_back: set[str] = set()
        self.calls = 0

    def _should_fall_back(self, raw: str) -> bool:
        if raw not in self._fallback_texts:
            return False
        if not self._fallback_once:
            return True
        if raw in self._already_fell_back:
            return False
        self._already_fell_back.add(raw)
        return True

    async def create(self, *, model: str, messages: list[dict], **kwargs) -> object:
        self.calls += 1
        raw = str(json.loads(messages[-1]["content"]).get("raw_text", ""))
        if self._should_fall_back(raw):
            return "<!doctype html>\n<html>gateway landing page</html>"
        return SimpleNamespace(
            choices=[
                SimpleNamespace(
                    message=SimpleNamespace(
                        content=json.dumps(
                            {
                                "corrected_text": raw,
                                "correction_applied": False,
                                "correction_reason": None,
                                "extracted": {"answer": "Nice to meet you"},
                                "intent_matched": True,
                                "intent": "provide",
                                "guidance": {"npc_line": None},
                                "confidence": 0.9,
                            },
                            ensure_ascii=False,
                        )
                    ),
                    finish_reason="stop",
                )
            ],
            model_dump=lambda mode="json": {"model": "mixed"},
        )


class _MixedClient:
    def __init__(self, fallback_texts: set[str], *, fallback_once: bool = False):
        self.chat = SimpleNamespace(
            completions=_MixedCompletions(fallback_texts, fallback_once=fallback_once)
        )


def _mixed_metrics(
    fallback_texts: set[str], *, repeats: int = 1, fallback_once: bool = False
) -> dict:
    from src.services.asr_postprocess import ASRPostprocessor

    cases = [_mixed_case("mx_ok", "Nice to meet you"), _mixed_case("mx_bad", "BOOM")]
    postprocessor = ASRPostprocessor(
        client=_MixedClient(fallback_texts, fallback_once=fallback_once)  # type: ignore[arg-type]
    )
    results = asyncio.run(run_eval(cases, postprocessor, repeats=repeats, concurrency=1))
    return compute_metrics(results, repeats=repeats, mode="live", model="mixed")


def test_provider_fallback_does_not_count_as_a_wrong_answer() -> None:
    """网关 500 不是模型的判决：不得计入准确率（否则网关抖动会伪装成准确度回归）。"""
    metrics = _mixed_metrics({"BOOM"})

    assert metrics["buckets"]["closed_set"]["accuracy"] == 1.0, "降级用例被算成了答错"
    assert metrics["buckets"]["closed_set"]["n"] == 1, "分母应为已落地判决的用例数"
    assert metrics["unscored_cases"] == ["mx_bad"]
    assert metrics["fallback_rate"] == 0.5


def test_fallback_rate_is_gated_separately() -> None:
    """容忍降级 ⇏ 放过降级：降级率飙升必须自己被门禁抓住。"""
    baseline = baseline_from_metrics(_mixed_metrics(set()))
    assert baseline["fallback_rate"] == 0.0

    degraded = _mixed_metrics({"BOOM"})
    gate = check_gate(degraded, baseline)

    assert not gate.passed
    assert any("降级率上升" in item for item in gate.failures), gate.failures


def test_fallback_repeat_is_not_counted_as_a_flip() -> None:
    """抖动率只看已落地判决：某次 repeat 降级不能让该例被判为"结论翻转"。"""
    metrics = _mixed_metrics({"BOOM"}, repeats=3, fallback_once=True)

    assert metrics["flipped_cases"] == [], "降级的那一次 repeat 被误判成翻转"
    assert metrics["flippable_cases"] == 2, "两个用例都有 >=2 次落地，均可判定抖动"
    assert metrics["overall_accuracy"] == 1.0
    assert metrics["fallback_rate"] < 0.5


def test_thin_bucket_is_not_ratcheted() -> None:
    """降级会把分母削薄：某桶只剩 1–2 例时不得用它的准确率判定退步或进步。"""
    big = [
        _mixed_case(f"mx_{index}", "Nice to meet you") for index in range(10)
    ]
    from src.services.asr_postprocess import ASRPostprocessor

    def run(cases):
        postprocessor = ASRPostprocessor(client=_MixedClient(set()))  # type: ignore[arg-type]
        results = asyncio.run(run_eval(cases, postprocessor, repeats=1, concurrency=1))
        return compute_metrics(results, repeats=1, mode="live", model="mixed")

    baseline = baseline_from_metrics(run(big))
    thin = run(big[:2])  # 只剩 2 例落地
    gate = check_gate(thin, baseline)

    assert any("样本不足" in note for note in gate.notes), gate.notes
    assert not any("退步" in item for item in gate.failures), gate.failures


# ────────────────────────────── 真实模型（opt-in） ──────────────────────────────

@pytest.mark.intent_eval
@pytest.mark.skipif(
    os.environ.get("INTENT_EVAL_LIVE") != "1",
    reason="真实模型评测会消耗预算：用 INTENT_EVAL_LIVE=1 pytest -m intent_eval 显式开启",
)
def test_live_baseline_gate() -> None:
    if not DEFAULT_BASELINE.exists():
        pytest.skip("尚无 live 基线：先跑 scripts/run_intent_eval.py --update-baseline")
    baseline = json.loads(DEFAULT_BASELINE.read_text(encoding="utf-8"))
    if baseline.get("mode") != "live":
        pytest.skip(f"仓库基线 mode={baseline.get('mode')}，不是 live 基线")

    from dotenv import load_dotenv

    load_dotenv(Path(__file__).resolve().parents[1] / ".env")
    cases = load_cases()
    postprocessor = build_postprocessor(stub=None, cases=cases)
    results = asyncio.run(run_eval(cases, postprocessor, repeats=1, concurrency=4))
    metrics = compute_metrics(results, repeats=1, mode="live", model=baseline.get("model"))
    gate = check_gate(metrics, baseline)
    assert gate.passed, gate.failures
