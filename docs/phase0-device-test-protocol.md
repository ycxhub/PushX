
pushup-coach/docs/phase0-device-test-protocol.md

Yeah, here are my observations. So what tends to happen is the rep counter starts even before I took a push-up position. 
You can see in the first part of the video where I am still standing. I am not in a plank position, 
but the reps have started counting. And the prompt I see on the screen is move whole body into the box, shift right. 
It comes in even without me taking the plank position. The concern here is that it should ideally be locking the position. 
The start position should be locked and only then rep counting should start. Right, that doesn't happen. 
Now, I see that the tracker is on. I can see the red dots. I can see it's tracking my hand, my face, you know, my shoulder, 
my chest, but it's not in green, right? I am doing the push-ups. As you can see, I can do the push-ups, but it's still in red. 
It's not tracking. However, if I kneel on my knees and I just show my hands, it moves to green. 
It moves to green if I stand vertically, right? But if I move to the plank position, it's in red. 
We need to establish why that's happening. And yeah, again, if you can see the reps getting counted, even without me doing reps. 
So yeah, the reps that are counted are only when I'm not actually doing a push-up. 
When I actually did a push-up, it's not getting counted. And I'm sharing the logs as well. 
I'm sharing the logs as you can see, but none of the counts are accurate. 
When I actually do the push-up, it doesn't count. But when I stand and move, it counts. 
And the prompts show up without, uh, without, uh, prompts that show up are not useful. 
They're not related to the user's actions. 

Ideally, the push-up position should be locked first and then once it's locked, the blue, sorry, 
the dots and the lines should turn green and it should start tracking as the shoulder moves down, chest moves down.

Here are the logs from the app.

[127.4] Start requested
[127.4] Camera authorization status: notDetermined
[131.9] Camera permission granted
[131.9] Selected provider: MediaPipe
[131.9] Configuring capture session
[131.9] startup: entered session queue
[131.9] startup: selected provider MediaPipe
[131.9] startup: began configuration
[131.9] startup: cleared previous inputs and outputs
[131.9] startup: resolved camera Front Camera
[131.9] startup: added input
[131.9] startup: added video output
[131.9] startup: configured portrait mirrored connection
[131.9] startup: committed configuration
[131.9] startup: invoking completion before startRunning()
[131.9] Capture session configured — waiting for first frame
[131.9] startup: calling startRunning()
[132.2] startup: startRunning() returned (isRunning=true)
[132.7] First frame processed — camera running
[133.3] Hold plank to lock start position (1/12)
[133.3] Hold plank to lock start position (2/12)
[133.4] Hold plank to lock start position (3/12)
[133.4] Hold plank to lock start position (4/12)
[133.4] Hold plank to lock start position (5/12)
[133.5] Hold plank to lock start position (6/12)
[133.5] Hold plank to lock start position (7/12)
[133.6] Hold plank to lock start position (8/12)
[133.6] Hold plank to lock start position (9/12)
[133.6] Hold plank to lock start position (10/12)
[133.7] Hold plank to lock start position (11/12)
[133.7] Start position locked — baseline noseY: 0.621
[161.3] Entering DOWN phase
[161.5] REP #1 counted! Duration: 0.20s
[170.1] Entering DOWN phase
[183.9] REP #2 counted! Duration: 13.89s
[211.4] Entering DOWN phase
[253.4] REP #3 counted! Duration: 42.04s
[256.2] Entering DOWN phase
[257.1] REP #4 counted! Duration: 0.88s
[263.1] Entering DOWN phase
[274.1] REP #5 counted! Duration: 11.00s
[278.2] Entering DOWN phase
[282.3] REP #6 counted! Duration: 4.10s
[285.0] Entering DOWN phase
[289.6] REP #7 counted! Duration: 4.54s
[291.8] Entering DOWN phase

And also, share your observations from the video that are absolutely critical for product to improve significantly. 








# Phase 0 — On-Device Manual Test Protocol

**Date:** _______________  
**Device:** _______________  
**iOS version:** _______________  
**Tester:** _______________  

---

## Setup

1. Build and install PushupCoach on your iPhone (iPhone 12 or newer recommended).
2. Find a well-lit room with a flat floor. Avoid backlighting (don't face a window).
3. Place the phone flat on the floor, screen facing up.
4. You'll be in pushup position above the phone, looking down at it.
5. Have a second device or printed copy of this checklist nearby.

---

## Test 1 — Camera Capture (P0-1)

**Goal:** Front camera activates and shows a live preview.

| Step | Action |
|------|--------|
| 1.1 | Launch the app. Confirm you see the Phase 0 start screen. | Pass
| 1.2 | Tap **Start Camera**. If prompted, grant camera permission. | Pass
| 1.3 | Verify the startup banner turns **green** ("State: Camera running"). | Pass 
| 1.4 | Verify the camera preview shows a live image from the **front** camera. |pass    
| 1.5 | Check the FPS counter in the top-right. Note the value: ______ FPS | 25 FPS Pass

**Pass criteria:**
- [x] Camera preview is live and responsive
- [x] Startup banner is green
- [x] FPS counter shows a value > 0

**Result:** PASS 
**Notes:** None

---

## Test 2 — MediaPipe BlazePose (P0-2)

**Goal:** MediaPipe returns landmarks at ≥10 FPS, drawn as dots on preview.

| Step | Action |
|------|--------|
| 2.1 | With camera running, confirm the provider shows **"MediaPipe"** in the top-right. | 
| 2.2 | Position yourself in pushup stance above the phone (~arm's length). | 
| 2.3 | Wait until the tracking state shows **"locked"** and landmark dots appear. |
| 2.4 | Note the FPS while landmarks are being drawn: ______ FPS |
| 2.5 | Count the approximate number of visible dots (should be many — head, shoulders, elbows, wrists, hips, legs). |

**Pass criteria:**
- [x] Provider label shows "MediaPipe"
- [x] Colored dots appear overlaid on your body in the camera view
- [x] Skeleton lines connect the dots
- [x] FPS ≥ 10 while tracking

**Result:** PASS
**Notes:** _______________

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

**Result:** PASS 
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
- [ ] No crash or hang during rapid switching
- [ ] Tracking resumes after switching
- [ ] Provider label updates correctly each time

**Result:** PASS  
**Notes:** App did not crash or freeze during switching, and provider label appeared to update. 
However, tracking was never reliably locked before switching, so successful tracking resumption could not be verified. 
Since the test requires switching during a locked tracking state and resumption after switching, 
this should be marked FAIL, not PASS.

---

## Test 5 — Landmark Confidence at Pushup Distance (P0-5)

**Goal:** Key landmarks detected with adequate confidence at ~2–3 feet in pushup position.

| Step | Action |
|------|--------|
| 5.1 | Get into pushup position above the phone (arms extended, ~arm's length). |
| 5.2 | Wait for tracking to lock. Check the top-left status dots: |
|     | — **Body**: green? ______ | 
|     | — **Landmarks**: green? ______ | 
|     | — **Distance**: green? ______ 
| 5.3 | Observe the landmark dots. Dots with high confidence are green; low confidence are yellow. Note the color of: |
|     | — Nose dot: ______ |
|     | — Shoulder dots: ______ |
|     | — Elbow dots: ______ |
| 5.4 | Tap **Copy Logs** in the debug panel. Paste into a note — we'll check confidence values later. |

**Pass criteria:**
- [ ] All three status dots (Body, Landmarks, Distance) are green
- [ ] Nose, shoulder, and elbow dots are green (not yellow), indicating ≥0.55 confidence
- [ ] Tracking state shows "locked"

**Result:** FAIL  
**Notes:** In actual pushup position, tracking did not reliably lock and key landmarks did not remain green. 
The system appeared able to detect some body parts, but confidence/validation in plank position remained very poor. 
Landmarks turned green easily in upright  or kneeling postures and never in the real pushup stance, 
which is the opposite of what the product needs.

---

## Test 6 — Calibration Checks (P0-6)

**Goal:** The app correctly distinguishes "in position" from "not in position" and "too close / too far."

### 6A — Not in position
| Step | Action |
|------|--------|
| 6A.1 | Tap **Reset** to clear state. |
| 6A.2 | Stand upright over the phone (not in pushup position). |
| 6A.3 | Check the coaching banner — it should show guidance like "Get on your front" or "Get arms visible." |
| 6A.4 | The phase should stay at **Idle**, not advance to Ready. |

- [ ] Coaching banner shows position guidance when not in pushup stance
- [ ] Phase stays Idle

### 6B — Too close
| Step | Action |
|------|--------|
| 6B.1 | Get very close to the phone (face ~6 inches away). |
| 6B.2 | Check if the **Distance** dot turns red and coaching says something about moving back. |

- [ ] Distance dot is red when too close
- [ ] Coaching prompts to move back

### 6C — Too far
| Step | Action |
|------|--------|
| 6C.1 | Move far from the phone (~6+ feet away) while still in frame. |
| 6C.2 | Check if the **Distance** dot turns red and coaching says something about moving closer. |

- [ ] Distance dot is red when too far
- [ ] Coaching prompts to come closer

### 6D — Correct position
| Step | Action |
|------|--------|
| 6D.1 | Get into proper pushup position at arm's length. |
| 6D.2 | Hold still for a few seconds. All three dots should turn green. |
| 6D.3 | Phase should advance from Idle → Ready (showing "Lower to begin"). |

- [ ] All dots green in correct position
- [ ] Phase reaches Ready

**Result:** FAIL  
**Notes:** The app does show coaching prompts while not in pushup stance, but it does not reliably 
keep the system in Idle. Rep logic and readiness logic appear to activate too early. 
Distance handling is inconsistent: some prompts appear, but the distance signal itself does not seem robust or trustworthy. 
In correct pushup position, the system does not reliably turn all dots green or reach a trustworthy Ready state.

---

## Test 7 — Rep Counting Accuracy (P0-7)

**Goal:** ≥90% accuracy vs. manual count.

Run **3 sets** of pushups. For each set, count your reps mentally and compare to the app's count.

### Set A — Slow, controlled (5 reps)
| Step | Action |
|------|--------|
| 7A.1 | Reset the session. Get into position. Wait for phase = Ready. |
| 7A.2 | Do **5 slow, full-range pushups** (2–3 seconds each). |
| 7A.3 | Record: Your count = ______, App count = ______ |

### Set B — Normal pace (10 reps)
| Step | Action |
|------|--------|
| 7B.1 | Reset. Get into position. Wait for Ready. |
| 7B.2 | Do **10 pushups** at a normal pace (~1.5 seconds each). |
| 7B.3 | Record: Your count = ______, App count = ______ |

### Set C — Fast pace (5+ reps)
| Step | Action |
|------|--------|
| 7C.1 | Reset. Get into position. Wait for Ready. |
| 7C.2 | Do **5+ fast pushups** (~1 second each). |
| 7C.3 | Record: Your count = ______, App count = ______ |

**Accuracy calculation:**

| Set | Manual | App | Match? |
|-----|--------|-----|--------|
| A   |        |     |        |
| B   |        |     |        |
| C   |        |     |        |
| **Total** | | | **___/___** = **____%** |

**Pass criteria:**
- [ ] Overall accuracy ≥ 90% (total app correct reps / total manual reps)
- [ ] No phantom reps counted when you are still (not exercising)
- [ ] Each individual set accuracy ≥ 80%

**Result:** FAIL  
**Notes:** Rep counting is fundamentally unreliable. The app counts reps while the user is standing or adjusting, 
but misses real pushups. Logs show clearly implausible rep durations such as 0.20s and 42.04s, 
indicating the rep state machine is firing on noise, drift, or incorrect phase transitions rather than true pushup cycles.

---

## Test 8 — Real-Time Latency (P0-8)

**Goal:** Rep count updates on screen within ~500ms of completing a rep.

| Step | Action |
|------|--------|
| 8.1 | During one of the sets above, pay attention to when the number increments. |
| 8.2 | Does the count update almost immediately after you reach the top of a rep? |
| 8.3 | Subjective latency: Instant / Slight delay / Noticeable lag |

**Pass criteria:**
- [ ] Count feels like it updates "right away" (no more than half a second)
- [ ] Rep count animation (bounce) fires on increment

**Result:** FAIL  
**Notes:** This cannot be considered a pass because rep increments themselves are not trustworthy. 
The bigger issue is not latency but incorrect triggering. Counts sometimes 
occur when no real rep has happened, and real reps are missed, so real-time response cannot be meaningfully validated.

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

**Result:** FAIL  
**Notes:** The UI does surface a frame-loss style message, but because tracking and rep counting are already unstable, 
pause/resume behavior cannot be trusted. 
There is no evidence that the count is preserved and resumed correctly in a deterministic way.

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

**Result:** FAIL  
**Notes:** Since pose validation and rep detection are not reliable in the actual pushup posture, 
any downstream form scoring is not trustworthy. 
Form scoring should not be considered validated until tracking, readiness, and rep counting are fixed first.
---

## Summary

| Test | P0 Req | Result |
|------|--------|--------|
| 1. Camera Capture | P0-1 | |
| 2. MediaPipe BlazePose | P0-2 | |
| 3. Apple Vision Fallback | P0-3 | |
| 4. Provider Switching | P0-4 | |
| 5. Landmark Confidence | P0-5 | |
| 6. Calibration Checks | P0-6 | |
| 7. Rep Counting Accuracy | P0-7 | |
| 8. Real-Time Latency | P0-8 | |
| 9. Pause / Resume | P0-9 | |
| 10. Form Scoring | P0-10 | |

**Overall Phase 0 verdict:** ______ / 10 passed

**Phase 0 gate:** All 10 must pass to proceed to Phase 1.  
If any fail, note the issue and we'll fix it before re-testing.

---

## After Testing

Paste these back into the chat:
1. The completed summary table above (with PASS/FAIL for each)
2. Any **Copy Logs** output from failed or interesting tests
3. The rep counting accuracy table from Test 7
4. The form score comparison from Test 10

We'll use this data to determine if Phase 0 is officially done.
