# /ycx-investigate — Systematic Root-Cause Debugging

## Iron Law

**NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.**

Fixing symptoms creates whack-a-mole debugging. Find the root cause, then fix it.

## Phase 1: Root Cause Investigation

1. **Collect symptoms:** Read error messages, stack traces, reproduction steps. If context is insufficient, ask ONE question at a time.

2. **Read the code:** Trace the code path from symptom back to potential causes. Use Grep to find all references.

3. **Check recent changes:**
   ```bash
   git log --oneline -20 -- <affected-files>
   ```
   Was this working before? What changed?

4. **Reproduce:** Can you trigger the bug deterministically? If not, gather more evidence.

Output: **"Root cause hypothesis: ..."** — a specific, testable claim.

## Phase 2: Pattern Analysis

| Pattern | Signature | Where to look |
|---------|-----------|---------------|
| Race condition | Intermittent, timing-dependent | Concurrent access to shared state |
| Nil/null propagation | NoMethodError, TypeError | Missing guards on optional values |
| State corruption | Inconsistent data | Transactions, callbacks, hooks |
| Integration failure | Timeout, unexpected response | External API calls, service boundaries |
| Configuration drift | Works locally, fails elsewhere | Env vars, feature flags, DB state |
| Stale cache | Shows old data | Redis, CDN, browser cache |

Also check: TODOS.md for related known issues, git log for prior fixes in the same area (recurring bugs = architectural smell).

## Phase 3: Hypothesis Testing

Before writing ANY fix:

1. **Confirm hypothesis:** Add a temporary log/assertion at the suspected root cause. Run reproduction. Does evidence match?

2. **If wrong:** Return to Phase 1. Gather more evidence. Do not guess.

3. **3-strike rule:** If 3 hypotheses fail, STOP. Ask the user:
   ```
   3 hypotheses tested, none match. This may be architectural.
   A) Continue — I have a new hypothesis: [describe]
   B) Escalate for human review
   C) Add logging and catch it next time
   ```

**Red flags:**
- "Quick fix for now" — there is no "for now"
- Proposing a fix before tracing data flow — you're guessing
- Each fix reveals a new problem — wrong layer, not wrong code

## Phase 4: Implementation

Once root cause is confirmed:

1. **Fix the root cause, not the symptom.** Smallest change that eliminates the actual problem.
2. **Minimal diff:** Fewest files touched, fewest lines changed.
3. **Regression test** that FAILS without the fix and PASSES with it.
4. **Run full test suite.** No regressions allowed.
5. **If fix touches >5 files:** Flag the blast radius before proceeding.

## Phase 5: Verification & Report

Reproduce the original bug scenario and confirm it's fixed. Run tests.

```
DEBUG REPORT
═══════════════════════════════
Symptom:         [what the user observed]
Root cause:      [what was actually wrong]
Fix:             [what was changed, file:line refs]
Evidence:        [test output, reproduction showing fix works]
Regression test: [file:line of new test]
Related:         [TODOS items, prior bugs in same area]
Status:          DONE | DONE_WITH_CONCERNS | BLOCKED
═══════════════════════════════
```

## Important Rules

- 3+ failed attempts → STOP and question the architecture
- Never apply a fix you cannot verify
- Never say "this should fix it" — prove it with test output
- If fix touches >5 files → ask about blast radius first
