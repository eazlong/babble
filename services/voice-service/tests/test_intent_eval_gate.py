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
    """费用记账要按『次』而不是按『例』——N=5 的一次全量跑是 350 次调用，不是 70 次。"""
    metrics = _run_stub("perfect", repeats=3)
    assert metrics["llm_calls_lower_bound"] == 70 * 3
    assert metrics["fallback_count"] == 0


def test_reserved_fields_keep_rule_layer_semantics() -> None:
    """为规则层（方向 C）预留的字段语义：降级不是判决，短路判决来源为 rule。"""
    assert _verdict_source({"applied": False, "fallback_reason": "missing_context"}) is None
    assert _verdict_source({"applied": True}) == "llm"
    assert _verdict_source({"applied": True, "shortcut_hit": True}) == "rule"
    metrics = _run_stub("perfect")
    assert metrics["shortcut_hits"] == 0, "规则层尚未落地，短路命中必须为 0"
    assert metrics["verdict_sources"] == ["llm"]


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
