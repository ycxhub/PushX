# Rep Engine Smoke Test — Single Comprehensive Test

**Date:** _______________
**Device:** _______________
**Build:** Rebuilt rep engine (Delta_rel gate, wrist anchor, ascending confirmation, 5s timeout)

---

## What changed in this build

| Feature | Old behavior | New behavior |
|---|---|---|
| **Descent gate** | Nose down + shoulders co-move (absolute) | Nose down + **Delta_rel > 0.02** (relative) + **wrist drift < 0.05** |
| **Rep counting** | Counted immediately on first return signal | Counted only after **4 frames confirmed near baseline** (ascending phase) |
| **Sway rejection** | Failed — equal nose/shoulder movement passed | **Rejected** — Delta_rel ≈ 0 when both move equally |
| **Whole-body slide** | Not detected | **Rejected** — wrist drift > 0.05 catches translation |
| **Stuck ascending** | Not possible (no ascending phase) | **5-second timeout** returns to ready without counting |
| **Phase enum** | `.up` (passthrough) | `.ascending` (real confirmation phase) |

---

## How to read the new logs

Each log line now starts with **`[F<frame> t<seconds>]`** — frame number since session start and wall-clock time. This lets you correlate with video.

**Key log lines and what they mean:**

```
LOCKED        — Baseline captured. Session is armed.
DOWN          — Descent detected. Nose/shoulder/wrist deltas shown.
ASCENDING     — Coming back up. Depth + duration gates passed. Awaiting return-to-top confirmation.
REP #N        — Rep counted after confirmed return to baseline.
REJECTED (X)  — Movement detected but rejected. Reason in parentheses.
TIMEOUT       — Entered ascending but never returned to baseline within 5 seconds.
```

**Key fields in each line:**

| Field | Meaning | Good pushup | Sway / phantom |
|---|---|---|---|
| `Δnose` | How far nose moved from baseline | 0.10–0.20 | 0.08–0.12 |
| `Δshldr` | How far shoulders moved from baseline | 0.04–0.10 | Same as Δnose |
| `Δrel` | Δnose − Δshldr (THE discriminator) | **> 0.02** (usually 0.04–0.12) | **≈ 0.00** |
| `wDrift` | How much wrists shifted from baseline | **< 0.05** | > 0.05 if sliding |
| `dur` | Rep duration in seconds | 0.5–4.0s | < 0.35s (too fast) |

---

## The Test — One session, five phases

### Setup

1. Build and install on your iPhone.
2. Well-lit room, flat floor.
3. Phone **vertically against a wall** at floor level, portrait, front camera facing you.
4. Stand 2–3 feet in front of the phone.
5. **Optional but recommended**: set up a second phone to record video from the side.

### Instructions

Do all five phases in ONE session without tapping Reset between phases.

| Phase | Action | Expected reps after phase |
|---|---|---|
| **A. Lock** | Launch app. Tap Start Camera. Get into plank. Hold still until LOCKED appears and subtitle says "Lower to begin". | 0 |
| **B. 3 slow pushups** | Do 3 slow, full-range pushups (~2–3 seconds each). Go all the way down, fully extend back up. Pause 1 second at top between reps. | 3 |
| **C. 3 sways (no pushup)** | Stay in plank. Lean your **whole body** forward ~6 inches, then rock back. Repeat 3 times. Do NOT bend your elbows. | Still 3 |
| **D. 2 more pushups** | Do 2 more slow, full-range pushups. | 5 |
| **E. Hold 5 seconds** | Hold completely still in plank for 5 seconds. Then tap **Copy Logs**. | Still 5 |

### What to report

After tapping Copy Logs, paste **everything** below. The clipboard now contains a session summary at the top plus the full log.

---

## Your report

### 1. Counts

| Phase | Expected reps (cumulative) | Actual app count |
|---|---|---|
| A. After lock | 0 | ______ |
| B. After 3 pushups | 3 | ______ |
| C. After 3 sways | 3 (no change) | ______ |
| D. After 2 more pushups | 5 | ______ |
| E. After 5s hold | 5 (no change) | ______ |

### 2. Observations

Write anything you noticed in plain English. Examples:
- "Rep 2 was counted before I fully returned to the top"
- "Sway #2 briefly showed Down phase on screen"
- "The app counted a phantom rep during the sway phase"
- "Hold phase was clean, no extra counts"

```
(your observations here)
```

### 3. Full log (paste from clipboard)

```
(paste everything here — session summary + all log lines)
```

### 4. For each REP line, mark real or phantom

| REP # in log | Phase it happened in | Real or Phantom? |
|---|---|---|
| REP #1 | | |
| REP #2 | | |
| REP #3 | | |
| REP #4 | | |
| REP #5 | | |
| (more if any) | | |

---

## Pass / Fail criteria

| Criterion | Pass | Fail |
|---|---|---|
| **Lock completes** | LOCKED line appears, phase = Ready, 0 reps | Lock never happens or reps > 0 after lock |
| **Real pushups counted** | 5 reps after phases B+D (4–5 acceptable) | < 4 or > 6 |
| **Sway rejected** | 0 reps added during phase C | Any REP line during sway phase |
| **Hold clean** | 0 reps added during phase E | Any REP line during hold |
| **No phantom reps** | Every REP line matches a real pushup you did | Any REP line you did not do a pushup for |
| **Delta_rel discriminates** | Real REP lines show Δrel > 0.02; REJECTED sway shows Δrel ≈ 0 | Real and phantom Δrel are indistinguishable |

**Overall verdict:** All 6 criteria pass → **PASS**. Any criterion fails → **FAIL** (note which one).

**Result:** _______________

---

## What the log tells me (for debugging)

When you paste the log, here's what I'll look at:

1. **Session summary block** — quick count of reps, rejections, timeouts
2. **LOCKED line** — baseline values are sane (nose > shoulder > wrist in Y)
3. **REP lines vs your Phase column** — do counted reps align with phases B and D only?
4. **Δrel on REP lines** — should all be > 0.02. If any are ≈ 0, the Delta_rel gate leaked
5. **wDrift on REP lines** — should all be < 0.05. If any are higher, wrist anchor leaked
6. **REJECTED lines during phase C** — these are GOOD, they mean the engine saw motion but refused to count it
7. **ASCENDING lines without matching REP** — means engine entered ascending but timed out or lost pose. Worth investigating
8. **Gaps in frame numbers** — dropped frames that might cause tracking issues
