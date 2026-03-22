# /ycx-ship — Fully Automated Ship Workflow

Non-interactive, fully automated. The user said `/ycx-ship` — DO IT. Run straight through and output the PR URL at the end.

**Only stop for:** base branch (abort), merge conflicts, test failures, ASK-level review findings, MINOR/MAJOR version bump.

## Step 0: Detect Base Branch

```bash
_BASE=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null || gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "main")
_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
echo "Branch: $_BRANCH | Base: $_BASE"
```

If on the base branch: "Ship from a feature branch." Abort.

## Step 1: Pre-flight

```bash
git status
git diff origin/$_BASE..HEAD --stat
git log origin/$_BASE..HEAD --oneline
```

## Step 2: Merge Base Branch

```bash
git fetch origin $_BASE && git merge origin/$_BASE --no-edit
```

If merge conflicts: try auto-resolve simple ones. Complex conflicts → STOP.

## Step 3: Run Tests

Detect and run the project's test command:
```bash
# Auto-detect test command
[ -f package.json ] && grep -q '"test"' package.json && echo "CMD:npm test"
[ -f Gemfile ] && echo "CMD:bundle exec rake test"
[ -f pytest.ini ] || [ -f pyproject.toml ] && echo "CMD:pytest"
[ -f go.mod ] && echo "CMD:go test ./..."
[ -f Cargo.toml ] && echo "CMD:cargo test"
[ -f Package.swift ] && echo "CMD:swift test"
```

Run the detected test command. If tests fail → STOP.

## Step 4: Test Coverage Audit

For every file changed in the diff:

1. Read the full file (not just diff hunks)
2. Trace every conditional branch, error path, and edge case
3. Check if tests exist for each path
4. Output ASCII coverage diagram:

```
CODE PATH COVERAGE
[+] src/services/billing.ts
    ├── processPayment()
    │   ├── [TESTED] Happy path — billing.test.ts:42
    │   ├── [GAP]    Network timeout — NO TEST
    │   └── [GAP]    Invalid currency — NO TEST
COVERAGE: 3/7 paths (43%) | GAPS: 4 need tests
```

Generate tests for uncovered paths. Run them. Commit passing tests.

## Step 5: Pre-Landing Review

Run the `/ycx-review` checklist against the diff:
- Pass 1 (CRITICAL): SQL safety, race conditions, trust boundaries
- Pass 2 (INFORMATIONAL): Dead code, magic numbers, test gaps

AUTO-FIX mechanical issues. ASK about judgment calls.

If fixes applied → commit them, re-run tests, confirm they pass.

## Step 6: Version Bump (if VERSION file exists)

- < 50 lines changed → MICRO bump (4th digit)
- 50+ lines → PATCH bump (3rd digit)
- MINOR/MAJOR → ASK the user

## Step 7: CHANGELOG (if exists)

Auto-generate from all commits on the branch:
```bash
git log origin/$_BASE..HEAD --oneline
```

Categorize: Added, Changed, Fixed, Removed. Insert after header, dated today.

## Step 8: TODOS.md Update

Read TODOS.md. Cross-reference against diff. Auto-mark completed items.

## Step 9: Commit (bisectable chunks)

Split changes into logical commits:
1. Infrastructure (migrations, config, routes) first
2. Models & services with their tests
3. Controllers & views with their tests
4. VERSION + CHANGELOG last

Each commit: `<type>: <summary>` (feat/fix/chore/refactor/docs)

## Step 10: Verification Gate

**If ANY code changed after Step 3 tests:** re-run the test suite. "Should work" is not evidence.

## Step 11: Push and Create PR

```bash
git push -u origin $_BRANCH
```

```bash
gh pr create --base $_BASE --title "<type>: <summary>" --body "$(cat <<'EOF'
## Summary
<bullet points>

## Test Coverage
<coverage diagram or "All paths covered">

## Pre-Landing Review
<findings summary>

## Test plan
- [x] All tests pass
EOF
)"
```

**Output the PR URL.**

## Step 12: Sync Docs

After PR is created, run the `/ycx-doc-sync` workflow: check if any .md files need updating based on the diff. If so, commit and push.

## Important Rules

- Never skip tests
- Never force push
- Never ask for trivial confirmations
- Never push without fresh verification evidence
- Split commits for bisectability
