#!/usr/bin/env python
"""回放验证：把规则层应用到**已存储的真实模型输出**上，量化它对验收目标的效果。

为什么需要它：把规则层接入 `ASRPostprocessor.process()` 会改动 `src/services/asr_postprocess.py`
（该文件当前有并发写入者）。本脚本让规则层的效果**在不接入生产路径的前提下**就能被验证 ——
输入是评测报告里逐例的真实模型判决（`cases_detail[*].actual`），输出是规则层处理后的判定与靶子变化。

用法：
    .venv/bin/python scripts/replay_intent_rules.py \
        --reports /tmp/eval_84_n5.json /tmp/new7_n5.json /tmp/new4_n5.json /tmp/verify16_n5.json

报告的逐例数据由 runner 的 `--json` 产出（nightly 脚本写进 tests/intent_eval/reports/）。

口径说明
- 输入文本用用例的 `raw_text`（报告里没有存 `corrected_text`）。生产路径会用 `corrected_text`；
  两者差异只在"模型是否顺手改过 ASR 错字"，而规则层的召回边界本就要求自己确认命中，故这是保守近似。
- 判定沿用评测的判分口径（归一化后比较 intent 与 extracted）。
- 两种模式都跑：`strict`（严格 rule_003，规则层不碰意图）与 `vetoes`（允许两处窄口径合法性归一）。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVICE_ROOT))

from src.services.intent_rules import RuleOptions, apply_rules  # noqa: E402
from tests.intent_eval.harness import load_cases, normalize_extracted  # noqa: E402


def load_model_outputs(paths: list[Path]) -> dict[str, dict]:
    outputs: dict[str, dict] = {}
    for path in paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        for case in data.get("cases_detail", []):
            # 后读的覆盖先读的：把最新的测量放在参数最后即可
            outputs[case["id"]] = case
    return outputs


def verdict_matches(expect: dict, intent: str, extracted: dict) -> bool:
    if expect.get("intent") != intent:
        return False
    if expect.get("extracted_match") == "ignore":
        return True
    return normalize_extracted(expect.get("extracted", {})) == normalize_extracted(extracted)


def run_mode(cases: list[dict], outputs: dict[str, dict], options: RuleOptions) -> dict:
    before_ok = after_ok = 0
    fixed: list[str] = []
    broken: list[str] = []
    rows: list[dict] = []
    skipped: list[str] = []
    for case in cases:
        stored = outputs.get(case["id"])
        if not stored:
            skipped.append(case["id"])
            continue
        model_intent = str(stored["actual"]["intent"])
        model_extracted = stored["actual"]["extracted"] or {}
        expect = case["expect"]
        before = verdict_matches(expect, model_intent, model_extracted)
        outcome = apply_rules(
            text=case["raw_text"],
            context=case["context"],
            model_intent=model_intent,
            model_extracted=model_extracted,
            options=options,
        )
        after = verdict_matches(expect, outcome.intent, outcome.extracted)
        before_ok += before
        after_ok += after
        if after and not before:
            fixed.append(case["id"])
        if before and not after:
            broken.append(case["id"])
        rows.append({
            "id": case["id"],
            "bucket": case["bucket"],
            "raw_text": case["raw_text"],
            "model": {"intent": model_intent, "extracted": model_extracted},
            "expect": {"intent": expect["intent"], "extracted": expect.get("extracted", {})},
            "after": {"intent": outcome.intent, "extracted": outcome.extracted},
            "rule": outcome.matched_rule,
            "before_ok": before,
            "after_ok": after,
        })
    return {"before_ok": before_ok, "after_ok": after_ok, "fixed": fixed, "broken": broken,
            "rows": rows, "skipped": skipped, "total": len(rows)}


def main() -> int:
    parser = argparse.ArgumentParser(description="把规则层回放到已存储的模型输出上")
    parser.add_argument("--reports", type=Path, nargs="+", required=True,
                        help="含 cases_detail 的评测报告 JSON（后读的覆盖先读的）")
    parser.add_argument("--show-fixed", action="store_true", help="逐条打印被修好的用例")
    parser.add_argument("--show-broken", action="store_true", help="逐条打印被弄坏的用例（应为空）")
    args = parser.parse_args()

    cases = load_cases()
    outputs = load_model_outputs(args.reports)
    print(f"用例 {len(cases)} 例；报告覆盖 {len(outputs)} 例")

    summary = {}
    # 注意：strict 必须**显式**关闭归一 —— RuleOptions 的默认为 True（2026-09-16 入契约），
    # 若这里写 RuleOptions() 两个模式会完全重合，回放就失去对照意义（曾踩到）。
    modes = (
        ("strict", "strict（关闭合法性归一）", RuleOptions(intent_vetoes=False)),
        ("default", "default（默认开启归一）", RuleOptions(intent_vetoes=True)),
    )
    for key, label, options in modes:
        result = run_mode(cases, outputs, options)
        summary[key] = result
        print()
        print(f"── 模式 {label} ───────────────────────────────────────────")
        print(f"  回放用例 {result['total']} 例"
              + (f"（缺报告 {len(result['skipped'])} 例）" if result["skipped"] else ""))
        print(f"  模型原判通过 {result['before_ok']} → 规则层处理后 {result['after_ok']}"
              f"（净 {result['after_ok'] - result['before_ok']:+d}）")
        print(f"  修好 {len(result['fixed'])} 例；弄坏 {len(result['broken'])} 例")
        if result["broken"]:
            print("  !! 弄坏:", ", ".join(result["broken"]))
        if args.show_fixed and result["fixed"]:
            for row in result["rows"]:
                if row["id"] in result["fixed"]:
                    print(f"    ✓ {row['id']}: 模型 {row['model']} → 规则层 {row['after']}"
                          f"（期望 {row['expect']}, 规则 {row['rule']}）")
        if args.show_broken and result["broken"]:
            for row in result["rows"]:
                if row["id"] in result["broken"]:
                    print(f"    ✗ {row['id']}: 模型 {row['model']} → 规则层 {row['after']}"
                          f"（期望 {row['expect']}, 规则 {row['rule']}）")

    # 验收目标清单与 docs/adr/0009 的"定义完成"保持一致（13 项）
    print()
    print("── 13 项验收目标在两种模式下的状态 ──────────────────────")
    targets = ["cs_009", "cs_040", "cs_041", "cs_043", "cs_044", "cs_045", "cs_046", "cs_047",
               "cs_058", "cs_061", "cs_065", "cs_066", "neg_017"]
    strict_rows = {r["id"]: r for r in summary["strict"]["rows"]}
    veto_rows = {r["id"]: r for r in summary["default"]["rows"]}
    print(f"{'用例':<9}{'模型':<10}{'strict':<10}{'default':<10}规则")
    for cid in targets:
        s, v = strict_rows.get(cid), veto_rows.get(cid)
        if not s:
            continue
        mark = lambda ok: "通过" if ok else "未过"
        print(f"{cid:<9}{mark(s['before_ok']):<10}{mark(s['after_ok']):<10}{mark(v['after_ok']):<10}{s['rule'] or '-'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
