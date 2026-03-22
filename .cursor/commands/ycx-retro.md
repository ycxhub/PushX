# /ycx-retro — Weekly Engineering Retrospective

Analyze commit history, work patterns, and code quality. Team-aware with per-person breakdowns.

## Arguments
- `/ycx-retro` — last 7 days (default)
- `/ycx-retro 14d` — last 14 days
- `/ycx-retro 30d` — last 30 days

## Step 1: Gather Data

Detect default branch and current user:
```bash
_DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "main")
git fetch origin $_DEFAULT --quiet
git config user.name
git config user.email
```

Parse the time argument. Default to 7 days. Compute midnight-aligned start date.

Run ALL data gathering in parallel:
```bash
# Commits with stats
git log origin/$_DEFAULT --since="<start>T00:00:00" --format="%H|%aN|%ae|%ai|%s" --shortstat

# Per-commit test vs production LOC
git log origin/$_DEFAULT --since="<start>T00:00:00" --format="COMMIT:%H|%aN" --numstat

# Timestamps for session detection
git log origin/$_DEFAULT --since="<start>T00:00:00" --format="%at|%aN|%ai|%s" | sort -n

# Hotspot files
git log origin/$_DEFAULT --since="<start>T00:00:00" --format="" --name-only | sort | uniq -c | sort -rn | head -15

# Per-author commit counts
git shortlog origin/$_DEFAULT --since="<start>T00:00:00" -sn --no-merges

# Test file count
find . -name '*.test.*' -o -name '*.spec.*' -o -name '*_test.*' -o -name '*_spec.*' 2>/dev/null | grep -v node_modules | wc -l
```

## Step 2: Metrics

| Metric | Value |
|--------|-------|
| Commits | N |
| Contributors | N |
| Insertions / Deletions | +N / -N |
| Net LOC | N |
| Test LOC ratio | N% |
| Active days | N |
| Sessions detected | N |
| Avg LOC/session-hour | N |

Per-author leaderboard (current user first, labeled "You"):
```
Contributor    Commits   +/-          Top area
You (name)         32   +2400/-300   src/
alice              12   +800/-150    tests/
```

## Step 3: Time Distribution

Hourly histogram:
```
Hour  Commits
 09:    5      █████
 10:    8      ████████
 ...
```

Call out: peak hours, dead zones, late-night clusters.

## Step 4: Session Detection

Use 45-minute gap threshold. For each session: start/end time, commits, duration.

Classify: Deep (50+ min), Medium (20-50), Micro (<20 min).

Calculate: total active time, average session length, LOC per active hour.

## Step 5: Commit Type Breakdown

Categorize by prefix (feat/fix/refactor/test/chore/docs):
```
feat:     20  (40%)  ████████████████████
fix:      27  (54%)  ███████████████████████████
```

Flag if fix ratio > 50% — signals potential review gaps.

## Step 6: Hotspot & Focus

Top 10 most-changed files. Flag files changed 5+ times (churn hotspots).

**Focus score:** % of commits touching the most-changed directory. Higher = focused work.

**Ship of the week:** Highest-LOC PR/commit in the window.

## Step 7: Team Analysis

For each contributor:
- Commits, LOC, areas of focus
- Commit type mix, session patterns
- **Praise** (1-2 specific things anchored in actual commits)
- **Growth opportunity** (1 specific, constructive suggestion)

## Step 8: Streak

```bash
git log origin/$_DEFAULT --format="%ad" --date=format:"%Y-%m-%d" | sort -u
```

Count consecutive days with commits from today backward.

## Step 9: Save & Compare

Save JSON snapshot to `.context/retros/{date}.json`. If prior retros exist, show trends:
```
              Last     Now      Delta
Test ratio:   22% →    41%      ↑19pp
Sessions:     10  →    14       ↑4
LOC/hour:     200 →    350      ↑75%
```

## Output Structure

**Tweetable summary** (first line):
`Week of {date}: {commits} commits, {LOC}k LOC, {test_ratio}% tests, peak: {hour} | Streak: {days}d`

Then: Summary Table → Trends → Time Patterns → Velocity → Quality → Focus → Your Week → Team → Top 3 Wins → 3 Improvements → 3 Habits for Next Week.

## Tone

Encouraging but candid. Specific and concrete — always anchor in actual commits. Skip generic praise. Frame improvements as leveling up, not criticism.
