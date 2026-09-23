# Context Map

This monorepo uses per-service CONTEXT.md files for domain-specific knowledge.

## Context Files

本仓库目前**只有下列 4 个 CONTEXT.md 存在**（2026-09 核验）。此前本表列出的
`dialogue/voice/spirit-coach/auth/quest/reward/assessment` 8 个文件在磁盘上不存在，
且所有链接都误写了 `../` 前缀（本文件在仓库根，`../` 会指向仓库之外）。

| Service/App | Context File |
|-------------|--------------|
| 根（跨服务领域语言） | [CONTEXT.md](CONTEXT.md) |
| summary-service | [services/summary-service/CONTEXT.md](services/summary-service/CONTEXT.md) |
| godot-client | [apps/godot-client/CONTEXT.md](apps/godot-client/CONTEXT.md) |
| parent-dashboard | [apps/parent-dashboard/CONTEXT.md](apps/parent-dashboard/CONTEXT.md) |

尚未建 CONTEXT.md 的服务：`dialogue-service`、`voice-service`、
`spirit-coach-service`、`auth-service`、`quest-service`、`reward-service`、
`assessment-service`。为这些服务新建文档后，请同时更新本表与 `docs/agents/domain.md`。

## ADR Location

- Root level: `docs/adr/` (shared architectural decisions)
- Per-service: `services/<name>/docs/adr/` (service-specific decisions)

## Usage

When working on a specific service, read its CONTEXT.md first to understand the domain language and architecture. 上表之外的服务当前没有领域文档——按目录名假设它存在会拿到死链。
