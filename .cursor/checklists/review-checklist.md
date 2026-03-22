# Code Review Checklist

## Pass 1 — CRITICAL (must check, can block ship)

### SQL & Data Safety
- [ ] No raw SQL with string interpolation (use parameterized queries)
- [ ] Migrations are backward-compatible and zero-downtime
- [ ] No `DELETE` or `UPDATE` without `WHERE` clause
- [ ] No `DROP TABLE` / `DROP COLUMN` without explicit plan
- [ ] Transactions wrap multi-step data mutations
- [ ] No N+1 queries introduced (check association traversals)

### Race Conditions & Concurrency
- [ ] No TOCTOU (time-of-check/time-of-use) patterns
- [ ] Shared mutable state is protected (locks, atomic ops, or immutability)
- [ ] No stale reads followed by writes (read-modify-write patterns)
- [ ] Background jobs are idempotent (safe to run twice)
- [ ] No assumption that two operations happen atomically unless in a transaction

### Trust Boundaries
- [ ] User input is validated/sanitized before use in SQL, shell, eval, templates
- [ ] LLM/AI output is validated before database writes or display
- [ ] File uploads are validated (type, size, content)
- [ ] API responses from external services are validated before use
- [ ] No secrets in code, logs, or error messages

### Enum & Value Completeness
- [ ] New enum values: ALL switch/case/match statements handle the new value
- [ ] New status/type/tier constants: ALL code paths that check siblings also check the new one
- **This requires reading code OUTSIDE the diff** — grep for sibling values

## Pass 2 — INFORMATIONAL (check, rarely blocks)

### Conditional Side Effects
- [ ] Side effects (API calls, DB writes, emails) not buried inside conditions that might not execute
- [ ] Feature flags don't hide untested codepaths

### Magic Numbers & String Coupling
- [ ] No hardcoded values that should be constants or config
- [ ] No string matching that should be enum/constant comparison

### Dead Code & Consistency
- [ ] No unreachable branches or unused imports
- [ ] Naming follows existing conventions
- [ ] No commented-out code left behind

### Test Gaps
- [ ] Every new conditional branch has a test for both paths
- [ ] Every new error handler has a test that triggers it
- [ ] Edge cases tested: nil input, empty collection, boundary values

### Performance & Bundle Impact
- [ ] No unbounded queries (missing LIMIT, pagination)
- [ ] No synchronous operations that should be async
- [ ] New dependencies justified (check bundle size impact)
- [ ] Images/assets optimized

### Frontend (web projects only)
- [ ] Loading states for async operations
- [ ] Error states with recovery paths
- [ ] Keyboard accessible (tab order, focus management)
- [ ] No `outline: none` without replacement focus indicator
- [ ] `font-size` >= 16px on mobile inputs (prevents iOS zoom)

## Fix-First Heuristic

| Finding type | Classification |
|---|---|
| Dead imports, unused variables | AUTO-FIX |
| Missing semicolons, formatting | AUTO-FIX |
| Obvious null check missing | AUTO-FIX |
| Stale comments referencing old code | AUTO-FIX |
| Race condition | ASK |
| Trust boundary violation | ASK |
| Architecture concern | ASK |
| Performance trade-off | ASK |
| Missing test for edge case | AUTO-FIX (write the test) |

## DO NOT Flag (suppressions)

- Style preferences not in project linter config
- "I would have done it differently" opinions
- Theoretical issues with no realistic trigger
- TODO comments (those go in TODOS.md)
