# Context Map

This monorepo uses per-service CONTEXT.md files for domain-specific knowledge.

## Context Files

| Service/App | Context File |
|-------------|--------------|
| dialogue-service | [services/dialogue-service/CONTEXT.md](../services/dialogue-service/CONTEXT.md) |
| voice-service | [services/voice-service/CONTEXT.md](../services/voice-service/CONTEXT.md) |
| spirit-coach-service | [services/spirit-coach-service/CONTEXT.md](../services/spirit-coach-service/CONTEXT.md) |
| auth-service | [services/auth-service/CONTEXT.md](../services/auth-service/CONTEXT.md) |
| quest-service | [services/quest-service/CONTEXT.md](../services/quest-service/CONTEXT.md) |
| reward-service | [services/reward-service/CONTEXT.md](../services/reward-service/CONTEXT.md) |
| assessment-service | [services/assessment-service/CONTEXT.md](../services/assessment-service/CONTEXT.md) |
| summary-service | [services/summary-service/CONTEXT.md](../services/summary-service/CONTEXT.md) |
| godot-client | [apps/godot-client/CONTEXT.md](../apps/godot-client/CONTEXT.md) |
| parent-dashboard | [apps/parent-dashboard/CONTEXT.md](../apps/parent-dashboard/CONTEXT.md) |

## ADR Location

- Root level: `docs/adr/` (shared architectural decisions)
- Per-service: `services/<name>/docs/adr/` (service-specific decisions)

## Usage

When working on a specific service, read its CONTEXT.md first to understand the domain language and architecture.