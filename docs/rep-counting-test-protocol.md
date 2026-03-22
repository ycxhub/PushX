# Rep Counting — On-Device Test Protocol

**Date:** _______________
**Device:** _______________
**Build:** post-phantom-fix (shoulder co-movement gate, min-duration gate, 6-frame hysteresis, diagnostic logging)

---

## Setup

1. Build and install PushupCoach on your iPhone.
2. Well-lit room, flat floor, no backlighting.
3. Phone **vertically against a wall** at floor level, portrait, screen facing you.
4. Stand 2–3 feet in front of the phone.
5. Have a second device to record video (optional but recommended for correlating real vs phantom reps with log data).

---

## How to read the new diagnostic logs

This build logs detailed joint coordinates on every phase transition. When you tap **Copy Logs**, the output now includes lines like:

```
LOCKED | nose=0.459 shldr=0.420 hip=0.480 rel=0.039
DOWN | nose=0.580 shldr=0.470 | Δnose=0.121 Δshldr=0.050 Δrel=0.071
REP #1 dur=1.24s | nose=0.490 shldr=0.425 | Δnose=0.140 Δshldr=0.080 Δrel=0.060 | peak: nose=0.620 shldr=0.500
REJECTED (too fast 0.18s) dur=0.18s | nose=0.510 shldr=0.440 | Δnose=0.060 Δshldr=0.040 Δrel=0.020
REJECTED (shallow) dur=0.55s | nose=0.520 shldr=0.430 | Δnose=0.030 Δshldr=0.010 Δrel=0.020
```

Key fields:
- **Δnose**: how far nose moved from baseline (bigger = deeper descent)
- **Δshldr**: how far shoulders moved from baseline
- **Δrel**: difference between Δnose and Δshldr (bigger = more "real pushup", near 0 = sway)
- **dur**: rep duration in seconds
- **REJECTED**: the engine detected but rejected this movement (reason in parentheses)

---

## Test RC-1 — Baseline Lock Still Works

**Goal:** Plank detection and 30-frame lock sequence still function correctly after changes.

| Step | Action |
|------|--------|
| 1.1 | Launch app. Tap **Start Camera**. |
| 1.2 | Get into plank position. Hold still. |
| 1.3 | Watch the debug log for "Hold plank to lock start position (X/30)". |
| 1.4 | Confirm it reaches 30/30 and you see a `LOCKED` log line. |
| 1.5 | Record the LOCKED line from the log: |

```
LOCKED | nose=______ shldr=______ hip=______ rel=______
```

| 1.6 | Confirm phase = **Ready** and subtitle = **"Lower to begin"**. |

**Pass criteria:**
- [ ] Lock counter increments to 30 in the debug log
- [ ] `LOCKED` log line appears with nose, shldr, hip, and rel values
- [ ] Phase transitions to Ready

**Result:** _______________
**Notes:** _______________

---

## Test RC-2 — Real Pushups Are Counted (Slow, 5 reps)

**Goal:** Slow, full-range pushups are counted accurately with correct diagnostic data.

| Step | Action |
|------|--------|
| 2.1 | Tap **Reset**. Get into plank. Wait for **Ready**. |
| 2.2 | Do **5 slow, full-range pushups** (2–3 seconds each). Go all the way down, fully extend back up. |
| 2.3 | After each rep, mentally note whether the app counted it. |
| 2.4 | After 5 reps, hold still in plank for 5 seconds (no movement). |
| 2.5 | Tap **Copy Logs**. |

Record:

| | Your count | App count |
|---|---|---|
| Slow set | 5 | ______ |

Paste the **full log** from LOCKED to the last rep here:
```
(paste log)
```

**Pass criteria:**
- [ ] App count = 5 (or 4–5, allowing ±1)
- [ ] All REP lines show `dur` between 1.5–4.0 seconds
- [ ] All REP lines show `Δrel` > 0.02 (nose moved more than shoulders — real pushup signature)
- [ ] No REJECTED lines during the 5-second hold after the last rep
- [ ] No phantom reps counted during the 5-second hold

**Result:** _______________
**Notes:** _______________

---

## Test RC-3 — Real Pushups Are Counted (Normal pace, 10 reps)

**Goal:** Normal-pace pushups are counted accurately.

| Step | Action |
|------|--------|
| 3.1 | Tap **Reset**. Get into plank. Wait for **Ready**. |
| 3.2 | Do **10 pushups** at normal pace (~1–1.5 seconds each). |
| 3.3 | Hold still for 5 seconds after the last rep. |
| 3.4 | Tap **Copy Logs**. |

Record:

| | Your count | App count |
|---|---|---|
| Normal set | 10 | ______ |

Paste the **full log** here:
```
(paste log)
```

**Pass criteria:**
- [ ] App count between 9–11 (≥90% accuracy)
- [ ] All REP lines show `dur` between 0.5–3.0 seconds
- [ ] All REP lines show `Δrel` > 0.02
- [ ] No phantom reps during the hold after the last rep

**Result:** _______________
**Notes:** _______________

---

## Test RC-4 — Phantom Rep Rejection: Forward/Backward Sway

**Goal:** Leaning forward and backward does NOT trigger reps.

| Step | Action |
|------|--------|
| 4.1 | Tap **Reset**. Get into plank. Wait for **Ready**. |
| 4.2 | **Without doing a pushup**, lean your whole body forward ~6 inches, then back. Repeat 5 times. |
| 4.3 | Check: did the app count any reps? ______ |
| 4.4 | Check: did the phase change to DOWN at any point? ______ |
| 4.5 | Tap **Copy Logs**. Look for any `DOWN` or `REP` or `REJECTED` lines. |

Paste any DOWN / REP / REJECTED lines here:
```
(paste lines, or "none")
```

**Pass criteria:**
- [ ] Rep count stays at **0** through all sway motions
- [ ] No `REP #` lines in the log
- [ ] If any `DOWN` lines appear, they should be followed by `REJECTED` (not a counted rep)
- [ ] Phase returns to Ready (not stuck in Down)

**Result:** _______________
**Notes:** _______________

---

## Test RC-5 — Phantom Rep Rejection: Shoulder Shaking

**Goal:** Shaking or rolling shoulders does NOT trigger reps.

| Step | Action |
|------|--------|
| 5.1 | Tap **Reset**. Get into plank. Wait for **Ready**. |
| 5.2 | **Without doing a pushup**, shrug your shoulders up and down 5 times. |
| 5.3 | Roll your shoulders in small circles. |
| 5.4 | Check: did the app count any reps? ______ |
| 5.5 | Tap **Copy Logs**. |

Paste any DOWN / REP / REJECTED lines here:
```
(paste lines, or "none")
```

**Pass criteria:**
- [ ] Rep count stays at **0**
- [ ] No `REP #` lines in the log

**Result:** _______________
**Notes:** _______________

---

## Test RC-6 — Phantom Rep Rejection: Head Bob

**Goal:** Nodding or bobbing the head alone does NOT trigger reps.

| Step | Action |
|------|--------|
| 6.1 | Tap **Reset**. Get into plank. Wait for **Ready**. |
| 6.2 | **Without doing a pushup**, nod your head down and up 5 times (move just your head, keep body still). |
| 6.3 | Check: did the app count any reps? ______ |
| 6.4 | Tap **Copy Logs**. |

Paste any DOWN / REP / REJECTED lines here:
```
(paste lines, or "none")
```

**Pass criteria:**
- [ ] Rep count stays at **0**
- [ ] If any `DOWN` lines appear, Δshldr should be near 0 (shoulders didn't move) and the movement should be REJECTED or never complete

**Result:** _______________
**Notes:** _______________

---

## Test RC-7 — Mixed Sequence: Real Reps + Deliberate Sway

**Goal:** The app counts only real pushups and ignores interleaved sway.

This is the most important test. It simulates a realistic session where the user does pushups but also shifts around.

| Step | Action |
|------|--------|
| 7.1 | Tap **Reset**. Get into plank. Wait for **Ready**. |
| 7.2 | Do this exact sequence: |
|     | 1. **2 real pushups** (count: 2) |
|     | 2. **Lean forward and back 3 times** (sway — should NOT count) |
|     | 3. **3 real pushups** (count: 5) |
|     | 4. **Shrug shoulders 3 times** (should NOT count) |
|     | 5. **2 real pushups** (count: 7) |
|     | 6. **Hold still 5 seconds** |
| 7.3 | Record: Your count = **7**, App count = ______ |
| 7.4 | Tap **Copy Logs**. |

Paste the **full log** here:
```
(paste log)
```

For each `REP #` line in the log, mark whether it was a real pushup or a phantom:

| Log line | Real or Phantom? | Notes |
|---|---|---|
| REP #1 | | |
| REP #2 | | |
| REP #3 | | |
| ... | | |

**Pass criteria:**
- [ ] App count = 7 (or 6–8, allowing ±1)
- [ ] Zero phantom reps from sway (steps 2 and 4 produce no REP lines)
- [ ] All REP lines correspond to a real pushup you performed
- [ ] REJECTED lines (if any) correspond to the sway/shrug movements — this is GOOD behavior

**Result:** _______________
**Notes:** _______________

---

## Test RC-8 — Minimum Duration Gate (Fast Reps)

**Goal:** Very fast pushups (< 0.35s each) are rejected, normal-speed ones are counted.

| Step | Action |
|------|--------|
| 8.1 | Tap **Reset**. Get into plank. Wait for **Ready**. |
| 8.2 | Do **3 extremely fast, shallow bounces** (not real pushups — just bounce your body quickly). |
| 8.3 | Then do **3 normal-speed real pushups**. |
| 8.4 | Tap **Copy Logs**. |

Record:

| Phase | Expected count | App count |
|---|---|---|
| Fast bounces | 0 | ______ |
| Real pushups | 3 | ______ |
| **Total** | **3** | ______ |

Paste the **full log** here:
```
(paste log)
```

**Pass criteria:**
- [ ] Fast bounces produce `REJECTED (too fast ...)` lines in the log
- [ ] Real pushups are counted (REP lines with `dur` > 0.5s)
- [ ] Total app count = 3 (or 2–3)

**Result:** _______________
**Notes:** _______________

---

## Test RC-9 — No Disruptive Prompts During Exercise

**Goal:** "Get down into pushup position" and "Move whole body into the box" do NOT appear once locked and doing pushups.

| Step | Action |
|------|--------|
| 9.1 | Tap **Reset**. Get into plank. Wait for **Ready**. |
| 9.2 | Do **5 pushups** at a normal pace. |
| 9.3 | During the pushups, watch the coaching banner at the top of the screen. |
| 9.4 | Did you see any of these messages DURING pushups? |
|     | — "Get down into pushup position": ______ (yes/no) |
|     | — "Move whole body into the box": ______ (yes/no) |
|     | — "Face the phone and get into plank": ______ (yes/no) |
| 9.5 | Were the exercise-related prompts (e.g. "Keep your hips level") still appearing when appropriate? ______ (yes/no/n/a) |

**Pass criteria:**
- [ ] "Get down into pushup position" NEVER appears during active pushups
- [ ] "Move whole body into the box" NEVER appears during active pushups
- [ ] Exercise-rule prompts (hips, shoulders) still work if relevant

**Result:** _______________
**Notes:** _______________

---

## Summary

| Test | Description | Result |
|------|-------------|--------|
| RC-1 | Baseline lock | |
| RC-2 | Slow pushups (5) | |
| RC-3 | Normal pushups (10) | |
| RC-4 | Sway rejection | |
| RC-5 | Shoulder shake rejection | |
| RC-6 | Head bob rejection | |
| RC-7 | Mixed sequence (real + sway) | |
| RC-8 | Fast bounce rejection | |
| RC-9 | No disruptive prompts | |

**Rep counting verdict:** ______ / 9 passed

**Gate:** RC-2, RC-3, RC-4, and RC-7 must ALL pass before moving to the next test area.

---

## After Testing

Paste these back into the chat:
1. The completed summary table
2. **All logs** from Copy Logs (especially RC-2, RC-3, RC-4, RC-7)
3. For any REP line you believe was a phantom, note the rep number and what you were doing at that moment

The new diagnostic logs (`Δnose`, `Δshldr`, `Δrel`) will let us compare real vs phantom reps and tune thresholds precisely.

**Optional (highly recommended):** Record a video of Test RC-7 on a second phone. Sync the video timestamp to the log timestamps. Tell me "Rep 3 was phantom — I was leaning forward" and I'll use the `Δrel` data to tighten the algorithm.
