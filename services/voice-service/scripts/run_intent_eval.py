#!/usr/bin/env python
"""意图判定评测运行器（Path A MVP）。

用法：
    # 离线自检（零成本，不发网络请求）
    .venv/bin/python scripts/run_intent_eval.py --stub perfect

    # 真实模型评测（消耗预算，读取 .env 里的 ASR_POSTPROCESS_* 配置）
    .venv/bin/python scripts/run_intent_eval.py --repeats 1 --max-calls 100

    # 抖动率（nightly/slow 通道，N=5）
    .venv/bin/python scripts/run_intent_eval.py --repeats 5 --limit 12 --max-calls 80

    # 显式更新基线（必须是一次独立提交）
    .venv/bin/python scripts/run_intent_eval.py --update-baseline

退出码：0 门禁通过 / 1 门禁失败 / 2 运行错误。
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
import unicodedata
from pathlib import Path

SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))

from dotenv import load_dotenv  # noqa: E402

from tests.intent_eval.harness import (  # noqa: E402
    DEFAULT_BASELINE,
    DEFAULT_CASES,
    DEFAULT_CONTEXTS,
    baseline_from_metrics,
    build_postprocessor,
    check_gate,
    compute_metrics,
    load_cases,
    load_pending_rulings,
    run_eval,
    sample_per_bucket,
)


def display_width(text: str) -> int:
    return sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in text)


def pad(text: str, width: int) -> str:
    return text + " " * max(0, width - display_width(text))


def fmt_pt(delta: float | None) -> str:
    if delta is None:
        return "—"
    return f"{delta * 100:+.1f}pt"


def print_report(metrics: dict, gate, baseline: dict | None, *, with_matrix: bool) -> None:
    print()
    print("═" * 72)
    print(
        f"意图判定评测  模式={metrics['mode']}  模型={metrics.get('model') or '—'}  "
        f"用例={metrics['cases']}  repeats={metrics['repeats']}"
        + ("  [partial]" if metrics.get("partial") else "")
    )
    print("═" * 72)
    base_buckets = (baseline or {}).get("buckets", {})
    print(pad("桶", 18) + pad("样本", 6) + pad("准确率", 10) + pad("与基线", 12) + "状态")
    print("─" * 72)
    threshold = metrics["thresholds"]["bucket_drop_pt"]
    for name, data in sorted(metrics["buckets"].items(), key=lambda kv: kv[1]["accuracy"]):
        base = base_buckets.get(name)
        delta = None if not base else data["accuracy"] - base["accuracy"]
        status = ""
        if delta is not None and delta < 0 and abs(delta) * 100 > threshold:
            status = "← 退步超阈"
        elif delta is not None and delta > 0:
            status = "↑"
        print(
            pad(name, 18)
            + pad(str(data["n"]), 6)
            + pad(f"{data['accuracy']:.3f}", 10)
            + pad(fmt_pt(delta), 12)
            + status
        )
    print("─" * 72)
    print(pad("总体准确率", 18) + pad(str(metrics["cases"]), 6) + f"{metrics['overall_accuracy']:.3f}")
    worst = metrics.get("min_bucket")
    if worst:
        base_worst = (baseline or {}).get("min_bucket")
        delta = None if not base_worst else worst["accuracy"] - base_worst["accuracy"]
        line = f"最差桶 = {worst['bucket']} ({worst['accuracy']:.3f}, 与基线 {fmt_pt(delta)})"
        if base_worst and base_worst.get("bucket") != worst["bucket"]:
            line += f"，基线最差桶为 {base_worst['bucket']}"
        print(line)
    flip = metrics.get("flip_rate")
    if flip is None:
        print("抖动率 = — （repeats=1，未测；按计划只在 nightly/slow 通道跑 N=5）")
    else:
        print(f"抖动率 = {flip:.3f}（N={metrics['repeats']}，翻转用例 {len(metrics['flipped_cases'])} 例）")
        if metrics["flipped_cases"]:
            print("  翻转用例：" + ", ".join(metrics["flipped_cases"][:12])
                  + ("…" if len(metrics["flipped_cases"]) > 12 else ""))
    print(
        f"调用统计：LLM 调用下界 {metrics['llm_calls_lower_bound']}  "
        f"fallback {metrics['fallback_count']}  短路命中 {metrics['shortcut_hits']}  "
        f"最慢 {metrics['max_latency_ms']}ms  总耗时 {metrics.get('duration_ms') or 0}ms"
    )
    if metrics["fallback_reasons"]:
        print("降级原因：" + ", ".join(metrics["fallback_reasons"]))
    if with_matrix:
        print()
        print("混淆矩阵（期望 → 实际）")
        for expected, row in sorted(metrics["confusion"].items()):
            cells = "  ".join(f"{actual}={count}" for actual, count in sorted(row.items()))
            print("  " + pad(expected, 14) + cells)
    print()
    if gate.failures:
        print("门禁：失败")
        for item in gate.failures:
            print("  ✗ " + item)
    else:
        print("门禁：通过")
    for note in gate.notes:
        print("  · " + note)
    print()


async def main_async(args: argparse.Namespace) -> int:
    if args.live:
        load_dotenv(SERVICE_ROOT / ".env")

    try:
        cases = load_cases(args.cases, args.contexts)
    except ValueError as exc:
        print(f"用例装载失败：{exc}", file=sys.stderr)
        return 2

    if args.bucket:
        wanted = set(args.bucket)
        unknown = wanted - {c["bucket"] for c in cases}
        if unknown:
            print(f"未知桶：{sorted(unknown)}；可用桶：{sorted({c['bucket'] for c in cases})}", file=sys.stderr)
            return 2
        cases = [c for c in cases if c["bucket"] in wanted]

    if args.sample_per_bucket:
        cases = sample_per_bucket(cases, args.sample_per_bucket)

    if args.limit:
        cases = cases[: args.limit]

    if not cases:
        print("没有可评测用例", file=sys.stderr)
        return 2

    partial = bool(args.bucket or args.limit or args.sample_per_bucket)
    planned_calls = len(cases) * args.repeats
    if args.max_calls and planned_calls > args.max_calls:
        print(
            f"预算闸门：本次计划 {len(cases)} 例 × {args.repeats} 次 = {planned_calls} 次调用，"
            f"超过 --max-calls {args.max_calls}。请调小 --limit/--repeats 或提高 --max-calls。",
            file=sys.stderr,
        )
        return 2

    mode = f"stub:{args.stub}" if args.stub else "live"
    postprocessor = build_postprocessor(stub=args.stub, cases=cases)

    if not args.quiet:
        print(
            f"开始评测：{len(cases)} 例 × {args.repeats} 次，模式={mode}，"
            f"并发={args.concurrency}，预计 LLM 调用 ≤ {planned_calls}"
        )
        if not args.stub:
            print("（live 模式：读取 .env 的 ASR_POSTPROCESS_BASE_URL / _MODEL / _API_KEY）")

    started = time.monotonic()
    results = await run_eval(
        cases,
        postprocessor,
        repeats=args.repeats,
        concurrency=args.concurrency,
        progress=not args.quiet,
    )
    duration_ms = int((time.monotonic() - started) * 1000)

    metrics = compute_metrics(
        results,
        repeats=args.repeats,
        mode=mode,
        model=args.model_label or (None if args.stub else _env_model()),
        partial=partial,
        durations_ms=duration_ms,
    )
    metrics["cases_detail"] = [r.to_dict() for r in results]

    baseline = None
    if args.baseline.exists():
        try:
            baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"基线文件损坏：{exc}", file=sys.stderr)
            return 2

    gate = check_gate(metrics, baseline)
    print_report(metrics, gate, baseline, with_matrix=args.matrix)

    failures = [r for r in results if not r.passed_first]
    if failures and not args.quiet:
        print(f"失败用例（{len(failures)}/{len(results)}，按桶）")
        for result in failures:
            print(f"  [{result.bucket}] {result.case_id}  {result.raw_text!r}")
            for reason in result.reasons:
                print("      " + reason)
        print()

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"完整报告已写入 {args.json}")

    if args.update_baseline:
        if partial and not args.force:
            print(
                "拒绝更新基线：本次是 partial 运行（用了 --bucket/--limit）。"
                "棘轮基线必须来自全量运行；如确需请加 --force。",
                file=sys.stderr,
            )
            return 2
        if args.stub and not args.allow_stub_baseline:
            print(
                "拒绝用 stub 结果更新基线：stub 只验证 harness 本身，不代表模型准确度。"
                "如确需请加 --allow-stub-baseline。",
                file=sys.stderr,
            )
            return 2
        if gate.failures and not args.force:
            print("拒绝更新基线：本次门禁失败，先修好再棘轮（或加 --force 明确覆盖）。", file=sys.stderr)
            return 2
        note = "stub 基线（仅用于 harness 自检）" if args.stub else None
        payload = baseline_from_metrics(metrics, note=note)
        args.baseline.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"基线已更新：{args.baseline}（这次更新必须作为独立提交 review）")

    return 0 if gate.passed else 1


def _env_model() -> str | None:
    import os

    return os.environ.get("ASR_POSTPROCESS_MODEL") or os.environ.get("COACH_LLM_MODEL") or "gpt-5.5"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="意图判定准确度评测（文字集，Path A MVP）")
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--contexts", type=Path, default=DEFAULT_CONTEXTS)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--bucket", action="append", default=[], help="只跑指定桶（可重复；标记为 partial）")
    parser.add_argument("--repeats", type=int, default=1, help="每例重复次数；>1 才计算抖动率")
    parser.add_argument("--limit", type=int, default=0, help="只跑前 N 例（标记为 partial，用于抖动率抽样）")
    parser.add_argument("--sample-per-bucket", type=int, default=0, dest="sample_per_bucket",
                        help="每桶等距抽 N 例（标记为 partial；抖动率抽样用）")
    parser.add_argument("--concurrency", type=int, default=4)
    parser.add_argument("--max-calls", type=int, default=0, help="LLM 调用次数上限（0=不限）")
    parser.add_argument("--stub", choices=["perfect", "off_topic", "delegate", "flaky"], default=None,
                        help="离线假客户端模式（零成本，仅验证 harness/门禁）")
    parser.add_argument("--no-live", dest="live", action="store_false", default=True,
                        help="不读取 .env（默认读取，live 模式需要）")
    parser.add_argument("--model-label", default=None, help="报告中显示的模型名（默认读环境变量）")
    parser.add_argument("--update-baseline", action="store_true")
    parser.add_argument("--allow-stub-baseline", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--json", type=Path, default=None, help="把完整报告（含逐例结果）写入该路径")
    parser.add_argument("--matrix", action="store_true", help="打印混淆矩阵")
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--list-buckets", action="store_true", help="列出用例分桶与待裁定用例数量")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.list_buckets:
        cases = load_cases(args.cases, args.contexts)
        counts: dict[str, int] = {}
        for case in cases:
            counts[case["bucket"]] = counts.get(case["bucket"], 0) + 1
        for name, count in sorted(counts.items()):
            print(f"{name}: {count}")
        pending = load_pending_rulings()
        print(f"(待裁定用例 {len(pending)} 条，不计入门禁)")
        return 0
    return asyncio.run(main_async(args))


if __name__ == "__main__":
    raise SystemExit(main())
