Logs

Fixed the issues. 

Here are the logs

[812.5] Hold plank to lock start position (26/30)
[812.5] Hold plank to lock start position (27/30)
[812.6] Hold plank to lock start position (28/30)
[812.6] Hold plank to lock start position (29/30)
[812.6] Start position locked — baseline noseY: 0.459
[812.8] Entering DOWN phase
[814.1] REP #1 counted! Duration: 1.24s
[817.0] Entering DOWN phase
[817.2] REP #2 counted! Duration: 0.20s
[819.1] Entering DOWN phase
[820.0] REP #3 counted! Duration: 0.96s
[821.3] Entering DOWN phase
[823.3] REP #4 counted! Duration: 1.93s
[824.8] Entering DOWN phase
[825.7] REP #5 counted! Duration: 0.84s
[827.0] Entering DOWN phase
[827.7] REP #6 counted! Duration: 0.72s
[829.4] Entering DOWN phase
[829.9] REP #7 counted! Duration: 0.52s
[831.2] Entering DOWN phase
[832.0] REP #8 counted! Duration: 0.76s
[833.5] Entering DOWN phase
[834.2] REP #9 counted! Duration: 0.68s
[835.6] Entering DOWN phase
[836.3] REP #10 counted! Duration: 0.68s
[837.9] Entering DOWN phase
[838.5] REP #11 counted! Duration: 0.56s
[840.0] Entering DOWN phase
[840.6] REP #12 counted! Duration: 0.60s
[841.9] Entering DOWN phase
[842.6] REP #13 counted! Duration: 0.68s
[844.0] Entering DOWN phase
[844.8] REP #14 counted! Duration: 0.84s
[846.1] Entering DOWN phase
[848.8] REP #15 counted! Duration: 2.69s
[850.3] Entering DOWN phase
[851.3] REP #16 counted! Duration: 1.00s
[851.9] Entering DOWN phase
[853.0] REP #17 counted! Duration: 1.08s
[853.7] Entering DOWN phase
[856.2] REP #18 counted! Duration: 2.53s
[856.6] Entering DOWN phase
[857.0] REP #19 counted! Duration: 0.48s
[858.8] Entering DOWN phase
[859.4] REP #20 counted! Duration: 0.60s
[860.9] Entering DOWN phase
[861.5] REP #21 counted! Duration: 0.68s
[868.7] Debug logs copied to clipboard
[870.2] Debug logs copied to clipboard
[871.0] Debug logs copied to clipboard


My Observations

A. Rep counter logic is unreliable

This is the main problem now.

Expected behavior
Rep counting should begin only after start position is locked
Rep counting should happen only for a valid push-up motion
Non-push-up movements should be ignored
Actual behavior
Real push-ups are often counted correctly
But non-push-up movements are also being counted:
moving forward
moving backward
shaking shoulders slightly
Your conclusion
The tracking layer is mostly good
The counter/state machine is the weak point

B. False-positive counting examples

You identified specific likely false counts in the logs:

Invalid reps
Rep 1: invalid
Rep 3: invalid
Rep 15: invalid
Rep 16: invalid
Rep 17: invalid
Valid reps
Rep 18: good
Rep 19: good
Rep 20: good
Most of the remaining reps seem good
Interpretation
Counting is partially accurate
But it is still too easy to trigger with incidental movement
This means the threshold/state logic is still too permissive

C. State / gating issues
Locking behavior
You expect counting to start only after push-up position is locked
That gating is still not strict enough in practice
Finishing-state detection issue
After going down and coming back up, the app is not consistently detecting the finishing/top state
This likely contributes to:
false counts
missed rep boundaries
prompts showing up at the wrong time
Likely system issue
The app can detect the body and joints
But it is not reliably distinguishing:
valid rep motion
incidental body movement
top/finish state after a rep

D. Prompt / UX feedback issues
Prompts that are unclear
“Move whole body into the box, shift right”
unclear because the user does not clearly perceive a meaningful box
the instruction references a UI concept that is not obvious
Prompts that are mostly fine
“Get down into push-up position”
“Keep your hips level, don’t let them sag”
Prompt timing problem

After the user is already locked and doing push-ups, the app still sometimes says:

“Get down into push-up position”
“Keep your hips level, don’t let them sag”
Why this is a problem
Once locked, “get down into push-up position” should not keep reappearing unless tracking truly dropped or the user fully left the valid posture
It suggests the app is not fully confident about the user’s current state, even during valid exercise motion


E. Framing / box-size feedback
Observation
The app may not be using the camera frame effectively enough
The current box feels too small
Suggested improvement
The active usable box should be much larger
Ideally it should use ~90% of the portrait camera viewport
A larger working region may help reduce unnecessary prompts and tracking friction
Product implication
The current ROI / framing region may be too restrictive
Users may be technically visible and tracked, but still treated as outside the ideal exercise zone

F. Root-cause hypotheses
Rep counting logic problem

Most likely issue:

rep engine is over-triggering on small body motion
forward/backward motion and shoulder shake are being mistaken for rep transitions

Finish/top-state detection problem
the app may not be reliably confirming a full return to top position
this can make counting boundaries messy

Prompt-state mismatch
prompting logic may still be tied to intermediate confidence drops
so even after lock, it sometimes behaves as if the user is not properly in position

Framing box too restrictive
ROI may be too tight relative to actual push-up motion



# Phase 0 — On-Device Manual Test Protocol (v2)

**Date:** _______________
**Device:** _______________
**iOS version:** _______________
**Tester:** _______________
**Build:** post-geometry-fix (`7405c8f`)

---

## Setup

1. Build and install PushupCoach on your iPhone (iPhone 12 or newer recommended).
2. Find a well-lit room with a flat floor. Avoid backlighting (don't face a window).
3. **Place the phone vertically against a wall or object at floor level**, portrait orientation (tall, not sideways), screen facing you.
4. Stand 2–3 feet in front of the phone. You should be able to see the screen from pushup position.
5. Have a second device or printed copy of this checklist nearby.

```
    Wall
  ┌───────┐
  │ Phone │    2-3 ft     You (standing, then plank)
  │  ↕    │  ←────────→       🧍 → 🏋️
  │ Front │
  │Camera │
  └───────┘
   Floor
```

---

## Test 1 — Camera Capture (P0-1)

**Goal:** Front camera activates and shows a live preview.

| Step | Action |
|------|--------|
| 1.1 | Launch the app. Confirm you see the Phase 0 start screen with instructions: "Lean phone against a wall, screen facing you." |
| 1.2 | Tap **Start Camera**. If prompted, grant camera permission. |
| 1.3 | Verify the startup banner turns **green** ("State: Camera running"). |
| 1.4 | Verify the camera preview shows a live image from the **front** camera. |
| 1.5 | Check the FPS counter in the top-right. Note the value: ______ FPS |

**Pass criteria:**
- [x] Camera preview is live and responsive
- [x] Startup banner is green
- [x] FPS counter shows a value > 0
- [x] Setup instructions mention wall placement (not flat on floor)

**Result:** PASS_______________
**Notes:** Camera start works. Live preview visible, startup state green, front camera active, FPS observed at ~24.9._______________

---

## Test 2 — MediaPipe BlazePose (P0-2)

**Goal:** MediaPipe returns landmarks at ≥10 FPS, drawn as dots on preview.

| Step | Action |
|------|--------|
| 2.1 | With camera running, confirm the provider shows **"MediaPipe"** in the top-right. |
| 2.2 | Stand 2–3 feet from the phone. You should see landmark dots appear on your body. |
| 2.3 | Wait until the tracking state shows **"locked"** and landmark dots appear. |
| 2.4 | Note the FPS while landmarks are being drawn: ______ FPS |
| 2.5 | Count the approximate number of visible dots (should be many — head, shoulders, elbows, wrists, hips, legs). |

**Pass criteria:**
- [x] Provider label shows "MediaPipe"
- [x] Colored dots appear overlaid on your body in the camera view
- [x] Skeleton lines connect the dots
- [x] FPS ≥ 10 while tracking

**Result:** PASS_______________
**Notes:** MediaPipe is active, landmarks and skeleton lines render, and push-up tracking geometry appears strong. FPS is comfortably above threshold._______________

---

## Test 3 — Apple Vision Fallback (P0-3)

**Goal:** Apple Vision also returns landmarks and draws dots.

| Step | Action |
|------|--------|
| 3.1 | Tap **Switch Provider** at the bottom. Provider should change to **"Apple Vision"**. |
| 3.2 | Wait for tracking to re-lock. Observe landmark dots. |
| 3.3 | Note the FPS: ______ FPS |
| 3.4 | Compare to MediaPipe: you should see fewer dots (Apple Vision has 11 joints vs 33). |
| 3.5 | Tap **Switch Provider** again to go back to MediaPipe for remaining tests. |

**Pass criteria:**
- [ ] Provider toggles to "Apple Vision" and back
- [ ] Dots appear on body with Apple Vision
- [ ] FPS ≥ 10 with Apple Vision

**Result:** _______________
**Notes:** _______________

---

## Test 4 — Provider Switching (P0-4)

**Goal:** Switching providers at runtime works without crashes or freezes.

| Step | Action |
|------|--------|
| 4.1 | While tracking is locked, tap **Switch Provider** rapidly 4–5 times. |
| 4.2 | The app should not crash or freeze. |
| 4.3 | After switching, tracking should resume within a few seconds. |

**Pass criteria:**
- [x] No crash or hang during rapid switching
- [x] Tracking resumes after switching
- [x] Provider label updates correctly each time

**Result:** PASS_______________
**Notes:** _______________

---

## Test 5 — Standing Rejection (NEW — Critical)

**Goal:** When standing upright in front of the phone, the app must NOT start counting reps.

| Step | Action |
|------|--------|
| 5.1 | Tap **Reset** to clear any previous state. |
| 5.2 | Stand upright 2–3 feet in front of the phone. Face the camera. |
| 5.3 | Wait 10 seconds. Observe: |
|     | — Does the coaching banner say "Get down into pushup position"? ______ |
|     | — Does the phase stay at **Idle** (not Ready)? ______ |
|     | — Is the rep count still **0**? ______ |
| 5.4 | Walk slowly left and right. Wave your arms. |
|     | — Does the rep count stay at **0**? ______ |
|     | — Does the phase stay at **Idle**? ______ |
| 5.5 | Sit down on the floor in front of the phone. |
|     | — Does the rep count stay at **0**? ______ |

**Pass criteria:**
- [x] Coaching banner tells user to get into pushup position while standing
- [x] Phase stays Idle the entire time (never reaches Ready)
- [x] Zero phantom reps counted while standing, walking, or sitting
- [x] No "Start position locked" message in the debug log while standing

**Result:** PASS_______________
**Notes:** _______________

---

## Test 6 — Plank Detection & Baseline Lock (NEW — Critical)

**Goal:** Getting into plank position triggers the 30-frame lock sequence and transitions to Ready.

| Step | Action |
|------|--------|
| 6.1 | From standing (after Test 5), get down into pushup/plank position facing the phone. Arms extended. |
| 6.2 | Hold plank position still. Observe the debug log — it should show "Hold plank to lock start position (X/30)." |
|     | — Does the counter increment frame by frame? ______ |
|     | — Does it take ~1–1.5 seconds to reach 30? ______ |
| 6.3 | Once it reaches 30/30, confirm: |
|     | — Debug log shows "Start position locked — baseline noseY: X.XXX" ______ |
|     | — Phase changes to **Ready** ______ |
|     | — Subtitle shows **"Lower to begin"** ______ |
| 6.4 | Check the top-left status dots: |
|     | — Body: green? ______ |
|     | — Landmarks: green? ______ |
|     | — Distance: green? ______ |
| 6.5 | Note the baseline noseY value from the log: ______ |

**Pass criteria:**
- [x] Lock counter counts up to 30 (visible in debug log)
- [x] Lock takes approximately 1–1.5 seconds (not instant)
- [ ] Phase transitions from Idle → Ready after lock completes
- [x] All three status dots are green in plank position
- [ ] "Lower to begin" subtitle appears

**Result:** FAIL
**Notes:** The locking sequence itself looks good now. This is a major improvement. I’m failing it only because Ready / “Lower to begin” were not explicitly verified in your notes or logs. If those were visible in the UI, this test would likely become PASS.
---

## Test 7 — Rep Counting Accuracy (P0-7)

**Goal:** ≥90% accuracy vs. manual count, with no phantom reps.

Run **3 sets** of pushups. For each set, count your reps mentally and compare to the app's count.

### Set A — Slow, controlled (5 reps)
| Step | Action |
|------|--------|
| 7A.1 | Reset the session. Get into plank. Wait for phase = **Ready** and "Lower to begin." |
| 7A.2 | Do **5 slow, full-range pushups** (2–3 seconds each). Go all the way down and fully extend up. |
| 7A.3 | Record: Your count = ______, App count = ______ |
| 7A.4 | Check debug log for rep durations. Are they plausible (1–3 seconds)? ______ |

### Set B — Normal pace (10 reps)
| Step | Action |
|------|--------|
| 7B.1 | Reset. Get into plank. Wait for Ready. |
| 7B.2 | Do **10 pushups** at a normal pace (~1.5 seconds each). |
| 7B.3 | Record: Your count = ______, App count = ______ |

### Set C — Fast pace (5+ reps)
| Step | Action |
|------|--------|
| 7C.1 | Reset. Get into plank. Wait for Ready. |
| 7C.2 | Do **5+ fast pushups** (~1 second each). |
| 7C.3 | Record: Your count = ______, App count = ______ |

### Accuracy calculation

| Set | Manual | App | Match? |
|-----|--------|-----|--------|
| A   |        |     |        |
| B   |        |     |        |
| C   |        |     |        |
| **Total** | | | **___/___** = **____%** |

**Pass criteria:**
- [ ] Overall accuracy ≥ 90% (total app reps / total manual reps)
- [ ] No phantom reps counted when holding still in plank before first pushup
- [ ] Each individual set accuracy ≥ 80%
- [ ] Rep durations in debug log are plausible (0.5–5 seconds, not 0.2s or 42s)

**Result:** FAIL
**Notes:** Real push-ups appear to count fairly well now, but phantom counts still happen when the user moves forward/backward or shakes shoulders. Log durations also still contain suspicious values like 0.20s, so the rep engine is improved but not production-safe.

---

## Test 8 — Real-Time Latency (P0-8)

**Goal:** Rep count updates on screen within ~500ms of completing a rep.

| Step | Action |
|------|--------|
| 8.1 | During one of the sets above, pay attention to when the number increments. |
| 8.2 | Does the count update almost immediately after you reach the top of a rep? |
| 8.3 | Subjective latency: Instant / Slight delay / Noticeable lag |
| 8.4 | Does the rep count animation (bounce) fire on each increment? ______ |

**Pass criteria:**
- [ ] Count feels like it updates "right away" (no more than half a second)
- [ ] Rep count animation (bounce) fires on increment

**Result:** FAIL
**Notes:** Latency itself may be acceptable, but not enough evidence was given to confidently pass this. Bounce animation was not confirmed.

---

## Test 9 — Pause / Resume on Frame Exit (P0-9)

**Goal:** Counting pauses when you leave frame and resumes when you return.

| Step | Action |
|------|--------|
| 9.1 | Start a set. Do 3 reps. Confirm count = 3. |
| 9.2 | Crawl or lean out of frame entirely (so the phone can't see you). |
| 9.3 | Wait 2–3 seconds. Observe: |
|     | — Does it show "Paused" or "Get back in frame"? ______ |
|     | — Does the rep count stay at 3 (no change)? ______ |
| 9.4 | Move back into pushup position in frame. |
| 9.5 | Wait for tracking to re-lock. Do 2 more reps. |
| 9.6 | Confirm count = 5 (3 before + 2 after). |

**Pass criteria:**
- [ ] "Get back in frame" or "Paused" shown when body leaves
- [ ] Rep count preserved (does not reset to 0)
- [ ] Counting resumes from where it left off
- [ ] Final count = pre-exit count + post-return reps

**Result:** _______________
**Notes:** No evidence shared for this test in the latest round.Will test this when the Rep counting accuracy increases by fixing the counting of phantom pushups.

---

## Test 10 — Form Scoring (P0-10)

**Goal:** Form scores differentiate intentionally good vs. bad form.

### 10A — Good form set
| Step | Action |
|------|--------|
| 10A.1 | Reset. Do **5+ pushups with the best form you can** — full depth, level shoulders, steady pace. |
| 10A.2 | Tap **Stop** to end the set and see the scores screen. |
| 10A.3 | Record scores: |
|       | — Composite: ______ |
|       | — Depth: ______ |
|       | — Alignment: ______ |
|       | — Consistency: ______ |
| 10A.4 | Note the improvement suggestions: ______ |

### 10B — Bad form set (intentionally)
| Step | Action |
|------|--------|
| 10B.1 | Tap **New Session**. Do **5+ pushups with intentionally uneven form**: |
|       | — Go shallow on some reps, deep on others |
|       | — Tilt one shoulder lower than the other |
|       | — Vary your speed (fast then slow) |
| 10B.2 | Tap **Stop**. Record scores: |
|       | — Composite: ______ |
|       | — Depth: ______ |
|       | — Alignment: ______ |
|       | — Consistency: ______ |
| 10B.3 | Note the improvement suggestions: ______ |

### Comparison

| Score | Good Form | Bad Form | Good > Bad? |
|-------|-----------|----------|-------------|
| Composite |      |          |             |
| Depth     |      |          |             |
| Alignment |      |          |             |
| Consistency |    |          |             |

**Pass criteria:**
- [ ] Good-form composite score > bad-form composite score
- [ ] At least 2 of 3 sub-scores are higher for good form
- [ ] Improvement suggestions are relevant (e.g., "go deeper," "keep shoulders level")
- [ ] Scores screen renders correctly with all sub-scores visible

**Result:** _______________
**Notes:** Not tested in the latest evidence. No evidence shared for this test in the latest round.Will test this when the Rep counting accuracy increases by fixing the counting of phantom pushups.
---

## Summary

| Test | P0 Req | Result |
|------|--------|--------|
| 1. Camera Capture | P0-1 | |
| 2. MediaPipe BlazePose | P0-2 | |
| 3. Apple Vision Fallback | P0-3 | |
| 4. Provider Switching | P0-4 | |
| 5. Standing Rejection | NEW | |
| 6. Plank Detection & Lock | P0-5/6 | |
| 7. Rep Counting Accuracy | P0-7 | |
| 8. Real-Time Latency | P0-8 | |
| 9. Pause / Resume | P0-9 | |
| 10. Form Scoring | P0-10 | |

**Overall Phase 0 verdict:** ______ / 10 passed

**Phase 0 gate:** All 10 must pass to proceed to Phase 1.
If any fail, note the issue and we'll fix it before re-testing.

---

## What changed since last test round

The previous test round (all tests 5–10 failed) revealed a fundamental geometry mismatch — the pose detection assumed the camera was looking up from the floor, but the phone is actually vertical against a wall looking forward. These fixes were applied:

1. **Plank detection rewritten** — now uses nose-below-shoulders (y-down) instead of elbow-below-shoulders. Standing (nose above shoulders, hips far below) is explicitly rejected.
2. **Baseline lock hardened** — requires 30 stable frames (~1.2s) instead of 12 (~0.5s). Prevents instant lock while standing.
3. **Rep thresholds raised** — down: 0.06→0.10, up: 0.03→0.05. Minimum depth gate (0.08) rejects head-bob phantom reps.
4. **Feedback engine updated** — shows "Get down into pushup position" when standing, "Face the phone and get into plank" for ambiguous poses.
5. **Test 5 (Standing Rejection) is new** — explicitly validates the core fix.

---

## After Testing

Paste these back into the chat:
1. The completed summary table above (with PASS/FAIL for each)
2. Any **Copy Logs** output from failed or interesting tests
3. The rep counting accuracy table from Test 7
4. The form score comparison from Test 10

We'll use this data to determine if Phase 0 is officially done.
