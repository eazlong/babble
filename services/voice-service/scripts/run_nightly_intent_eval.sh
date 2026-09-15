#!/usr/bin/env bash
# 意图判定 nightly 评测：N=5 全量 + 双门禁，产出 JSON 报告并与上一次对比。
#
# 计划文档：docs/plans/2026-09-15-intent-accuracy.md（§5 度量口径）
#
# 用法：
#   bash scripts/run_nightly_intent_eval.sh                 # 正常 nightly（N=5，约 350 次 LLM 调用）
#   INTENT_EVAL_REPEATS=1 INTENT_EVAL_MAX_CALLS=80 bash scripts/run_nightly_intent_eval.sh   # 省预算
#   INTENT_EVAL_STUB=perfect bash scripts/run_nightly_intent_eval.sh                          # 零成本验管线
#
# 环境变量：
#   INTENT_EVAL_REPEATS      默认 5（抖动率门禁需要 >1）
#   INTENT_EVAL_MAX_CALLS    默认 400（费用闸门；超出直接拒绝运行）
#   INTENT_EVAL_BASELINE     默认 tests/intent_eval/baseline.json
#   INTENT_EVAL_REPORTS_DIR  默认 tests/intent_eval/reports（已在 .gitignore）
#   INTENT_EVAL_STUB         留空 = 真实模型；perfect/off_topic/delegate/flaky = 离线假客户端
#   PYTHON                   默认 .venv/bin/python，缺失时回退 python3
set -euo pipefail

cd "$(dirname "$0")/.."

REPEATS="${INTENT_EVAL_REPEATS:-5}"
MAX_CALLS="${INTENT_EVAL_MAX_CALLS:-400}"
BASELINE="${INTENT_EVAL_BASELINE:-tests/intent_eval/baseline.json}"
REPORTS_DIR="${INTENT_EVAL_REPORTS_DIR:-tests/intent_eval/reports}"
PYTHON="${PYTHON:-.venv/bin/python}"
[ -x "$PYTHON" ] || PYTHON="python3"

STUB_ARGS=()
if [ -n "${INTENT_EVAL_STUB:-}" ]; then
  STUB_ARGS=(--stub "$INTENT_EVAL_STUB")
fi

mkdir -p "$REPORTS_DIR"
STAMP="$(date +%Y%m%dT%H%M%S)"
REPORT="$REPORTS_DIR/intent_eval_${STAMP}.json"

echo "nightly 意图判定评测  repeats=$REPEATS  max_calls=$MAX_CALLS"
echo "baseline=$BASELINE  报告=$REPORT"
[ -n "${INTENT_EVAL_STUB:-}" ] && echo "⚠️  stub 模式：只验管线，不代表模型准确度"

set +e
"$PYTHON" scripts/run_intent_eval.py \
  --repeats "$REPEATS" \
  --max-calls "$MAX_CALLS" \
  --baseline "$BASELINE" \
  --json "$REPORT" \
  --matrix \
  ${STUB_ARGS[@]+"${STUB_ARGS[@]}"}
STATUS=$?
set -e

if [ -f "$REPORT" ]; then
  "$PYTHON" - "$REPORTS_DIR" "$REPORT" <<'PY' || true
import json
import pathlib
import sys

reports_dir, current_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
cur = json.loads(current_path.read_text(encoding="utf-8"))
mode = cur.get("mode")

# 只与**同模式**的上一次报告比较：stub 报告是管线自检，与 live 结果不可比。
previous = [
    path
    for path in sorted(reports_dir.glob("intent_eval_*.json"))
    if path != current_path and json.loads(path.read_text(encoding="utf-8")).get("mode") == mode
]

if not previous:
    print("趋势：暂无同模式（%s）的历史报告可比" % mode)
else:
    prev = json.loads(previous[-1].read_text(encoding="utf-8"))

    def fmt(value):
        return "—" if value is None else value

    print("趋势（上一次同模式报告 %s → 本次）：" % previous[-1].name)
    print("  最差桶准确率  %s → %s" % (fmt((prev.get("min_bucket") or {}).get("accuracy")),
                                        fmt((cur.get("min_bucket") or {}).get("accuracy"))))
    print("  抖动率        %s → %s" % (fmt(prev.get("flip_rate")), fmt(cur.get("flip_rate"))))
    print("  总体准确率    %s → %s" % (fmt(prev.get("overall_accuracy")), fmt(cur.get("overall_accuracy"))))
    print("  最慢单次(ms)  %s → %s" % (fmt(prev.get("max_latency_ms")), fmt(cur.get("max_latency_ms"))))
PY
fi

echo "报告：$REPORT"
if [ "$STATUS" -eq 0 ]; then
  echo "门禁：通过"
else
  echo "门禁：失败（退出码 $STATUS）——按计划应视为阻断，不要顺手更新 baseline"
fi
exit "$STATUS"
