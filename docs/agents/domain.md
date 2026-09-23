# Domain Docs Configuration

## Layout

multi-context — separate CONTEXT.md per service

现状（2026-09 核验）：**只有 4 个 CONTEXT.md 实际存在且已入库**。
下表是权威清单；新增 CONTEXT.md 时请同时更新本文件与根 `CONTEXT-MAP.md`。

## Context Files

```
CONTEXT.md                             # 根：跨服务通用领域语言（游戏流程/录音/评估）
services/summary-service/CONTEXT.md    # 学习总结与掌握度
apps/godot-client/CONTEXT.md           # 客户端领域模型
apps/parent-dashboard/CONTEXT.md       # 家长控制台
```

尚无 CONTEXT.md 的服务（按需补建）：`dialogue-service`、`voice-service`、
`spirit-coach-service`、`auth-service`、`quest-service`、`reward-service`、
`assessment-service`。

## ADR Location

Root level: `docs/adr/`（0001–0009）。服务级 ADR 若存在，放在 `services/<name>/docs/adr/`。

## Consumer Rules

Skills reading domain docs:
1. Read `CONTEXT-MAP.md` first to locate relevant context
2. Read the CONTEXT.md(s) that exist for the service(s) being worked on —— 上表之外的服务默认没有领域文档，不要按目录名假设它存在
3. Check for ADRs in root `docs/adr/` or the context's `docs/adr/`