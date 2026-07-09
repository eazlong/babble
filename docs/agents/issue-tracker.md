# Issue Tracker Configuration

## Tracker Type

GitHub Issues

## CLI Tool

`gh` (GitHub CLI)

## External PRs as Request Surface

No — only GitHub Issues are triaged. External PRs are not processed.

## Workflow

1. **Create issues**: `gh issue create`
2. **List issues**: `gh issue list`
3. **View issue**: `gh issue view <number>`
4. **Close issue**: `gh issue close <number>`
5. **Add labels**: `gh issue edit <number> --add-label <label>`

## Notes

- This is a monorepo with multiple services/apps
- Issues should be scoped to specific services when possible
- Use labels to categorize by service/component