#!/usr/bin/env bash
# Godot headless verification wrapper for LinguaQuest.
# Usage:
#   scripts/godot-test.sh check              # parse/check-only
#   scripts/godot-test.sh import             # import newly added assets (生成 .import)
#   scripts/godot-test.sh gut                # full GUT suite
#   scripts/godot-test.sh gut <test-file>    # single GUT test file
#   scripts/godot-test.sh gut <test-file> <method>
#
# NOTE: 跑项目（headless 或编辑器外）**不会**导入新加的资源：新 PNG 没有 .import/.ctex，
# 运行时 load() 会失败。往 assets/ 里丢新资源后必须跑一次 `import`。
#
# Godot headless only runs inside a DSH session from a workspace COPY of the
# .app (macOS taskgated SIGKILLs the /Applications binary under the sandbox).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT="$ROOT/apps/godot-client"

# Prefer a workspace copy (sandbox-safe), fall back to the system binary.
if [ -x "$ROOT/.dsh-godot/Godot.app/Contents/MacOS/Godot" ]; then
  GODOT="$ROOT/.dsh-godot/Godot.app/Contents/MacOS/Godot"
else
  GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
fi

# Redirect Godot user dirs into the workspace so user:// writes stay in-tree.
export HOME="${CLIENT}/.godot-home"
export XDG_DATA_HOME="${CLIENT}/.godot-home"
export XDG_CACHE_HOME="${CLIENT}/.godot-home"
mkdir -p "${CLIENT}/.godot-home"

cd "$CLIENT"

CMD="${1:-}"
shift || true
case "$CMD" in
  check)
    "$GODOT" --headless --quit --check-only --path . 2>&1 | tail -40
    ;;
  import)
    # --import：起编辑器、等资源导入完、退出（隐含 --editor --headless）。
    # 这是让新 PNG/WAV/OGG 在运行时能被 load() 到的唯一途径。
    "$GODOT" --headless --path . --import 2>&1 | tail -20
    ;;
  gut)
    ARGS=(-gconfig=gutconfig.json -gexit)
    if [ $# -ge 1 ] && [ -n "$1" ]; then ARGS+=("-gtest=$1"); fi
    if [ $# -ge 2 ] && [ -n "$2" ]; then ARGS+=("-gunit_test_name=$2"); fi
    "$GODOT" --headless --script addons/gut/gut_cmdln.gd "${ARGS[@]}" 2>&1 | tail -60
    ;;
  *)
    echo "usage: $0 {check|import|gut [test-file] [test-method]}" >&2
    exit 2
    ;;
esac
