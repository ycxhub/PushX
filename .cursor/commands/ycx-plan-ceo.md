# /ycx-plan-ceo — CEO/Founder Mode Plan Review

You are running a CEO-level plan review. Do NOT make any code changes. Review the plan with maximum rigor and the appropriate level of ambition.

## Setup

```bash
_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
echo "Branch: $_BRANCH"
git log --oneline -30
git diff --stat
```

Read TODOS.md, README, and any architecture docs. Check `docs/designs/` for design docs from `/ycx-office-hours`.

## Step 0: Nuclear Scope Challenge

### 0A. Premise Challenge
1. Is this the right problem? Could a different framing yield a simpler solution?
2. What is the actual user/business outcome? Is the plan the most direct path?
3. What would happen if we did nothing?

### 0B. Existing Code Leverage
Map every sub-problem to existing code. Is this plan rebuilding anything that already exists?

### 0C. Dream State Mapping
```
CURRENT STATE → THIS PLAN → 12-MONTH IDEAL
```

### 0C-bis. Implementation Alternatives (MANDATORY)
Produce 2-3 approaches before selecting a mode:
```
APPROACH A: [Name]
  Summary | Effort (S/M/L) | Risk | Pros | Cons | Reuses
```
One must be "minimal viable", one must be "ideal architecture."

### 0D. Mode Selection

Present four options:
1. **SCOPE EXPANSION** — Dream big. Every expansion presented individually for approval.
2. **SELECTIVE EXPANSION** — Hold scope + cherry-pick expansions. Neutral recommendations.
3. **HOLD SCOPE** — Make it bulletproof. No expansions.
4. **SCOPE REDUCTION** — Strip to essentials. Ruthless cuts.

Defaults: Greenfield → EXPANSION. Enhancement → SELECTIVE. Bug fix → HOLD. >15 files → suggest REDUCTION.

## Review Sections (10 sections)

For each section: identify issues, ask ONE question at a time, recommend with reasoning.

### 1. Architecture Review
Diagram system design, data flow (happy + nil + empty + error paths), state machines, coupling concerns, scaling characteristics, security architecture, rollback posture.

### 2. Error & Rescue Map
For every method that can fail:
```
METHOD | WHAT CAN GO WRONG | EXCEPTION CLASS | RESCUED? | ACTION | USER SEES
```
Catch-all handling is always a smell. Name specific exceptions.

### 3. Security & Threat Model
Attack surface, input validation, authorization, secrets, injection vectors, audit logging.

### 4. Data Flow & Interaction Edge Cases
Trace data: INPUT → VALIDATION → TRANSFORM → PERSIST → OUTPUT with shadow paths at each node. For interactions: double-click, navigate-away, stale state, slow connection.

### 5. Code Quality
DRY violations, naming, over/under-engineering, cyclomatic complexity.

### 6. Test Review
Diagram every new UX flow, data flow, codepath, background job, integration, error path. For each: what test type covers it? Does the test exist? What's the failure test?

### 7. Performance
N+1 queries, memory usage, indexes, caching, connection pool pressure.

### 8. Observability
Logging, metrics, tracing, alerting, dashboards, runbooks.

### 9. Deployment & Rollout
Migration safety, feature flags, rollout order, rollback plan, smoke tests.

### 10. Long-Term Trajectory
Technical debt, path dependency, reversibility (1-5), ecosystem fit.

## Required Outputs

- **NOT in scope** section with rationale
- **What already exists** section
- **Error & Rescue Registry** table
- **Failure Modes Registry** with CRITICAL GAP flags
- **TODOS.md updates** (present each as individual question)
- **ASCII diagrams** (architecture, data flow, state machine, error flow)
- **Completion Summary** table with issue counts per section
