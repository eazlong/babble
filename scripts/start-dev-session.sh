#!/bin/bash
# LinguaQuest MVP - 快速启动开发会话脚本
# 用法: ./scripts/start-dev-session.sh [A|B|C|all]

SESSION=${1:-all}

echo "=== LinguaQuest RPG MVP 开发会话 ==="
echo "会话: $SESSION"
echo ""

case $SESSION in
  A) echo "轨道 A: 后端服务"; cat "scripts/prompts/session-A.txt" ;;
  B) echo "轨道 B: CocosCreator 客户端"; cat "scripts/prompts/session-B.txt" ;;
  C) echo "轨道 C: 家长控制台"; cat "scripts/prompts/session-C.txt" ;;
  all)
    echo "=== 3 条并行开发轨道 ==="
    echo ""
    echo "轨道 A (后端): 在新 Claude Code 会话中运行:"
    echo "  cd $(pwd) && claude"
    echo "  然后粘贴 prompts/session-A.txt 的内容"
    echo ""
    echo "轨道 B (客户端): 在新 Claude Code 会话中运行:"
    echo "  cd $(pwd) && claude"
    echo "  然后粘贴 prompts/session-B.txt 的内容"
    echo ""
    echo "轨道 C (家长控制台): 在新 Claude Code 会话中运行:"
    echo "  cd $(pwd) && claude"
    echo "  然后粘贴 prompts/session-C.txt 的内容"
    echo ""
    echo "=== Prompt 文件内容 ==="
    echo ""
    echo "--- session-A.txt ---"
    cat scripts/prompts/session-A.txt
    echo ""
    echo "--- session-B.txt ---"
    cat scripts/prompts/session-B.txt
    echo ""
    echo "--- session-C.txt ---"
    cat scripts/prompts/session-C.txt
    ;;
  *)
    echo "用法: $0 [A|B|C|all]"
    exit 1
    ;;
esac
