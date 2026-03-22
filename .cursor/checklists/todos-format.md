# TODOS.md Canonical Format

## Structure

TODOS.md should be organized by component/area, then by priority within each section.

```markdown
# TODOS

## [Component/Area Name]

### [TODO Title]
**Priority:** P0 (critical) | P1 (urgent) | P2 (important) | P3 (nice-to-have) | P4 (someday)
**Added:** YYYY-MM-DD
**Context:** Why this matters. Enough detail that someone picking it up in 3 months
understands the motivation, current state, and where to start.
**Depends on:** [other TODOs or external blockers, if any]
**Effort:** S/M/L/XL (human team) → with AI: S→S, M→S, L→M, XL→L

---

## Completed

### [Completed TODO Title]
**Priority:** P2
**Added:** 2026-03-01
**Completed:** v1.2.0 (2026-03-15)
**Context:** [original context preserved]
```

## Priority Definitions

| Priority | Meaning | Timeline |
|----------|---------|----------|
| P0 | Critical — blocks users or causes data loss | Fix today |
| P1 | Urgent — significant UX or reliability issue | Fix this week |
| P2 | Important — meaningful improvement | Next sprint |
| P3 | Nice-to-have — polish, optimization | When convenient |
| P4 | Someday — ideas, explorations | No timeline |

## Rules

1. **Every TODO has a Priority and Context** — bare bullet points are not acceptable
2. **Completed items move to the bottom** — never delete, always preserve history
3. **Group by component** — not by priority (priority is a field, not a heading)
4. **P0/P1 items at the top** of each component section
5. **Review weekly** — stale P2+ items should be promoted, completed, or dropped
6. **Cross-reference PRs** — when a PR addresses a TODO, note it in both places
