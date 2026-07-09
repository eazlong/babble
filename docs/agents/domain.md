# Domain Docs Configuration

## Layout

multi-context — separate CONTEXT.md per service

## Context Map

Root `CONTEXT-MAP.md` points to per-service CONTEXT.md files.

## Context Files

```
services/dialogue-service/CONTEXT.md
services/voice-service/CONTEXT.md
services/spirit-coach-service/CONTEXT.md
services/auth-service/CONTEXT.md
services/quest-service/CONTEXT.md
services/reward-service/CONTEXT.md
services/assessment-service/CONTEXT.md
apps/godot-client/CONTEXT.md
apps/parent-dashboard/CONTEXT.md
```

## ADR Location

Each context may have its own `docs/adr/` or share root-level `docs/adr/`.

## Consumer Rules

Skills reading domain docs:
1. Read CONTEXT-MAP.md first to locate relevant context
2. Read the appropriate CONTEXT.md(s) for the service(s) being worked on
3. Check for ADRs in the context's docs/adr/ or root docs/adr/