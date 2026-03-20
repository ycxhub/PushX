# PRD: PushupCoach — Real-Time Camera-Based Pushup Tracker (iOS)

## 1. Introduction / Overview

PushupCoach is a native iOS app that uses the phone's **front (selfie) camera** and **on-device pose estimation** to count pushup reps in real time, score form after each set, and guide users through progressive training plans.

The phone is placed on the ground **in front of the user** in **landscape orientation** so they can see the screen while in pushup position. The app detects body landmarks (head, shoulders, elbows, chest) from the front-facing camera, counts reps as the user moves through down→up cycles, and after each set computes a form score with actionable improvement suggestions.

### Problem it solves

- Counting reps manually is distracting and error-prone, especially when fatigued.
- Most people have no way to measure or improve pushup form without a trainer.
- Existing fitness apps either require manual logging or use awkward side-angle camera placement where the user can't see the screen.

### Why the front camera angle

- The user can **read on-screen prompts** without turning their head.
- The user can **see the live rep count** during the set.
- The calibration flow (stance confirmation, distance guide) is visible and interactive.
- Side-angle placement forces the user to look sideways, making on-screen instructions impractical.

---

## 2. Goals

| # | Goal | Measurable target |
|---|------|-------------------|
| G1 | Real-time rep counting | Rep count updates within 500 ms of a completed cycle |
| G2 | Accurate form scoring | Form score correlates with manual expert review ≥ 80% of the time |
| G3 | Guided setup/calibration | ≥ 90% of first-time users complete calibration without confusion |
| G4 | Streak engagement | ≥ 40% of active users maintain a 7-day streak in the first month |
| G5 | Subscription conversion | ≥ 8% of free-trial users convert to paid within 30 days |
| G6 | Privacy-first, on-device processing | Zero video frames leave the device; zero cloud compute for pose |

---

## 3. User Stories

### 3.1 First-time user

> As a beginner who can't do many pushups, I want the app to guide me through setting up my phone, confirm I'm in the right position, and count my reps automatically — so I can focus on the exercise, not the counting.

### 3.2 Improving user

> As someone who can do 10–15 pushups, I want to see a form score after each set with specific suggestions (like "go deeper" or "keep hips level") — so I can improve technique over time.

### 3.3 Streak-motivated user

> As a daily exerciser, I want to see my streak, weekly activity, and progress toward my training plan goal on the home screen — so I feel motivated to keep going.

### 3.4 AI coaching user (premium)

> As a premium subscriber, I want to chat with an AI coach that knows my stats, streak, plan progress, and recent form scores — so I can get personalized advice without hiring a trainer.

### 3.5 Plan follower

> As a beginner targeting 25 pushups, I want to follow a structured plan (e.g., 0→10) that tells me how many reps and sets to do each day — so I have a clear path to my goal.

---

## 4. Functional Requirements

### 4.1 Camera & Pose Detection

| # | Requirement |
|---|-------------|
| FR-1 | The app uses **only the front (selfie) camera**. No rear camera mode. |
| FR-2 | Pose estimation runs **on-device**. The primary model is **MediaPipe BlazePose** (via CoreML/TFLite), chosen for its higher accuracy on fitness poses (33 landmarks, 45.0 mAP on fitness benchmarks). The fallback model is **Apple Vision** (`VNDetectHumanBodyPoseRequest`, 19 landmarks, 32.8 mAP). See Section 7.1 for the model-switching architecture. |
| FR-3 | The app detects at minimum these landmarks from the front angle: **nose, left/right eye, left/right shoulder, left/right elbow, left/right wrist, left/right hip, and chest/torso midpoint**. MediaPipe provides all 33; Apple Vision provides a subset of 19. |
| FR-4 | Pose inference runs at **≥ 10 fps** on iPhone 12 and newer (minimum supported device). |
| FR-5 | No video frames, images, or raw camera data are stored to disk or transmitted over the network. All pose processing happens in-memory only. |

### 4.2 Calibration & Setup Flow

| # | Requirement |
|---|-------------|
| FR-6 | When the user taps "Start Pushups," the app shows a **Ready Screen** with a setup guide: (a) place phone on floor in front of you, screen facing you, in **landscape** orientation, (b) ensure good lighting (avoid backlighting), (c) keep your full upper body visible in the camera. |
| FR-7 | The Ready Screen includes an illustration showing the **recommended phone distance: approximately 2–3 feet** (60–90 cm) in front of the user's head, on the floor, leaning slightly against an object so the screen is angled toward the user's face. |
| FR-8 | The app requests **camera permission** on the Ready Screen if not already granted. |
| FR-9 | After the user taps "I'm Ready," the camera activates and the app enters **Stance Confirmation** mode. The app checks that: (a) a human body is detected, (b) key landmarks (head, shoulders, elbows) are visible with sufficient confidence, (c) the user appears to be in a pushup-ready position (arms extended, body roughly horizontal). |
| FR-10 | If the user is NOT in a good stance, the app shows **real-time coaching prompts** overlaid on the camera preview. These prompts actively guide the user into position. Examples: "Move back a bit — I can't see your elbows," "Get into pushup position — arms straight," "Too close — move the phone further away," "Good! Hold that position." |
| FR-11 | The app validates **phone distance** using landmark sizing: if key landmarks (shoulder span) appear too large (phone too close) or too small (phone too far), it prompts the user to adjust. Target: landmarks occupy roughly 30–60% of the frame width. |
| FR-12 | Once the stance is confirmed (all checks pass for ≥ 2 seconds of stable detection), a **3-second countdown** appears before tracking begins. This gives the user a moment to settle. |
| FR-13 | The stance confirmation screen clearly displays a **green checkmark** for each passed check (body detected, landmarks visible, distance OK, position OK) so the user knows what's good and what still needs adjustment. |

### 4.3 Real-Time Rep Counting (Core)

| # | Requirement |
|---|-------------|
| FR-14 | Rep counting is **camera-based only**. There is no manual tap-to-count button in v1. |
| FR-15 | The app identifies the **"down" phase** (head/shoulders move closer to camera / lower in frame) and **"up" phase** (head/shoulders move away / higher in frame). |
| FR-16 | A full rep is counted when the user completes a **down → up cycle**. Partial reps (not reaching sufficient depth or not fully extending) are not counted but are tracked internally for form scoring. |
| FR-17 | The rep count updates on screen **within 500 ms** of the "up" phase completing. |
| FR-18 | The counting logic uses **smoothing and hysteresis** to prevent: (a) double-counting from jitter, (b) counting non-pushup movements (adjusting position, resting). The user must pass a minimum movement threshold for a rep to register. |
| FR-19 | During tracking, the screen displays: **current rep count** (large, readable from pushup position), optional **skeleton/landmark overlay** on the camera preview, and simple **live form hints** (e.g., "Good depth," "Go lower," "Keep steady"). |
| FR-20 | **If the user's body leaves the camera frame mid-set**, the app **pauses counting** and shows a prominent warning: "I lost you — get back into position." When the user's body is detected again and stable for ≥ 1 second, counting **resumes automatically** from where it left off. |

### 4.4 Sets, Rest Periods & Workout Session

| # | Requirement |
|---|-------------|
| FR-21 | The user can configure a **target rep count** before starting (with quick-select presets: 5, 10, 15, 20, 25, custom). |
| FR-22 | When a set is complete (target reached or user taps "End Set"), the app enters a **rest period** with a 60-second countdown timer. The user can skip or extend the rest. |
| FR-23 | After rest, the next set begins with a short 3-second countdown (no full re-calibration needed if pose is still detected). |
| FR-24 | The user can end the entire workout at any time. |

### 4.5 Post-Workout Summary

| # | Requirement |
|---|-------------|
| FR-25 | After the workout ends, the app shows a **summary screen** containing: total reps, number of sets, total duration, form accuracy score (0–100), and average tempo (seconds per rep). **No calorie estimation** (too imprecise without user biometrics and sets wrong expectations). |
| FR-26 | The **form score (0–100)** is a composite of three sub-scores, each also displayed: |
|     | — **Depth score**: how consistently the user reached full pushup depth across reps. |
|     | — **Alignment score**: how straight/level the shoulders and head remained (no excessive tilting or asymmetry). |
|     | — **Consistency score**: how uniform the rep tempo and range of motion were across the set. |
| FR-27 | Below the score, the app shows a **ranked suggested improvement list** (e.g., "1. Try going deeper on each rep — your last 3 reps were shallower than your first 5," "2. Keep your head neutral — you tend to look up"). |
| FR-28 | The summary is **automatically saved** to the user's session history (stored locally and synced to the backend). |

### 4.6 Home Dashboard

| # | Requirement |
|---|-------------|
| FR-29 | The home screen shows: **animated streak flame** (current streak in days), **weekly activity dots** (7 dots, filled = workout done), **today's total rep count**, and a prominent **"Start Pushups" quick-start button**. |
| FR-30 | A **form tips carousel** rotates through short tips (e.g., "Keep your core tight," "Breathe out on the way up"). |
| FR-31 | An **AI Coach promo card** is shown to free/non-premium users, prompting them to try AI coaching. |

### 4.7 Training Plans

| # | Requirement |
|---|-------------|
| FR-32 | Three built-in progressive plans: **0→10 pushups**, **10→25 pushups**, **25→50 pushups**. Pure pushups only — no other exercises or warm-ups. |
| FR-33 | Each plan is structured as a **multi-week program** with: number of weeks, training days per week, target reps per set, number of sets, and rest guidance. |
| FR-34 | The user can **activate one plan at a time**. The app tracks daily completion within the plan and shows a progress bar. |
| FR-35 | Plans **auto-advance**: when the user completes the prescribed workout for a day, the plan moves to the next day. When all days in a week are done, the plan advances to the next week. No manual advancement required. |
| FR-36 | Plan content is **static and bundled** in v1 (not generated by AI). |

### 4.8 Streaks

| # | Requirement |
|---|-------------|
| FR-37 | A streak increments by 1 for each **calendar day** the user completes at least one workout session. |
| FR-38 | Missing a day resets the streak to 0. |
| FR-39 | The current streak is displayed on the Home Dashboard and Profile screen. |

### 4.9 AI Coach (Premium / Paywalled)

| # | Requirement |
|---|-------------|
| FR-40 | The AI Coach is a **chat interface** where the user can ask questions and get personalized pushup advice. |
| FR-41 | The AI has access to the user's **context**: current streak, active plan + progress, recent session history (reps, sets, form scores, improvement suggestions), and total lifetime stats. |
| FR-42 | The chat shows **suggested prompt buttons** (e.g., "How can I improve my form?", "Am I ready for the next plan?", "Why does my shoulder hurt?"). |
| FR-43 | The backend uses the **OpenAI Chat Completions API** (GPT-4o or latest). A system prompt injects the user's stats/context before each conversation. The API key is held server-side on the backend (never in the app binary). |
| FR-44 | **Fallback**: if the device is offline or the API is unreachable, the app attempts to use **Apple's on-device Foundation Models** (available on iOS 18.x+ with Apple Intelligence). It shows a "limited mode" notice. If neither is available, the chat shows an offline message. |
| FR-45 | The AI Coach is **only accessible to premium subscribers**. Free users see a locked state with a prompt to subscribe. |

### 4.10 Paywall & Subscription

| # | Requirement |
|---|-------------|
| FR-46 | New users get **5 free pushup sets** (total, not per day). The free sets include full camera counting, form scoring, and summary — so users experience the core value before paying. |
| FR-47 | Free-set usage is tracked **server-side, tied to the user's Apple ID** (via Sign in with Apple). This prevents bypass by reinstalling the app. |
| FR-48 | After 5 free sets, all workout features are locked behind a subscription. |
| FR-49 | Subscription tiers: **$4.99/month** or **$19.99/year**. Managed via Apple StoreKit 2 with server-side receipt validation. |
| FR-50 | The paywall is a **polished modal** with: animated entry, feature highlights (AI Form Coach, Smart Recommendations, Advanced Analytics), pricing cards for both tiers, and a clear CTA. |
| FR-51 | There is **no ongoing free tier** after the 5-set trial. |

### 4.11 User Accounts & Authentication

| # | Requirement |
|---|-------------|
| FR-52 | The app uses **Sign in with Apple** as the sole authentication method. |
| FR-53 | Account creation is required before the first workout (to tie free-set tracking and session history to the account). |
| FR-54 | User profile data, session history, streaks, and plan progress are **synced to the backend** so data persists across device reinstalls and (in future) device transfers. |

### 4.12 Profile Screen

| # | Requirement |
|---|-------------|
| FR-55 | The Profile screen shows: **stats grid** (total lifetime pushups, current streak, total workouts, average reps per set), **current active plan** with progress, and **recent session history** (last 10–20 sessions with date, reps, score). |

### 4.13 Form Guide

| # | Requirement |
|---|-------------|
| FR-56 | A static **Form Guide** screen with categorized tips: hand placement, body alignment, breathing technique, common mistakes. |
| FR-57 | Each tip includes a **title, description, and illustrative image** (static assets bundled with the app). |

### 4.14 Data Persistence & Sync

| # | Requirement |
|---|-------------|
| FR-58 | **Local storage**: Core Data for session history, plan progress, and cached data. UserDefaults for lightweight preferences. Data is available offline. |
| FR-59 | **Backend sync**: session summaries, streaks, plan progress, and account data sync to the backend when the device is online. Local-first: the app works fully offline and syncs when connectivity returns. |
| FR-60 | No raw video or image data is ever written to disk or sent to the backend. Only structured metrics (reps, scores, timestamps) are stored/synced. |

---

## 5. Non-Goals (Out of Scope for v1)

| # | Explicitly excluded |
|---|---------------------|
| NG-1 | **Android version** — iOS only in v1. |
| NG-2 | **Rear camera mode** — front (selfie) camera only. |
| NG-3 | **Manual tap-to-count mode** — camera counting only in v1. |
| NG-4 | **Video recording or storage** — no frames saved to disk, ever. |
| NG-5 | **Cloud-based pose processing** — all vision/ML runs on-device. |
| NG-6 | **Social features** (leaderboards, sharing, friends). |
| NG-7 | **Other exercises** — pushups only in v1. |
| NG-8 | **Adaptive/dynamic training plans** (plans are static in v1). |
| NG-9 | **Apple Watch companion app**. |
| NG-10 | **Calorie estimation** — too imprecise without biometrics. |
| NG-11 | **iCloud sync** — backend handles sync instead. |

---

## 6. Design Considerations

### Visual identity

- **Palette**: warm coral (#FF6B6B or similar) as the primary accent on a dark charcoal (#1A1A2E / #16213E) background. Inspired by Nike Training Club's energetic-but-clean aesthetic.
- **Typography**: San Francisco (system font) for clarity; large, bold rep counters readable from pushup distance (~2–3 feet away).
- **Cards**: rounded corners, subtle shadows, clean spacing.
- **Animations**: streak flame animation on home, animated paywall entry, smooth counter increment, subtle haptic feedback on rep count.

### Key screens

1. **Home Dashboard**: streak flame (top), weekly dots, today's reps, quick-start button, tips carousel, AI promo card.
2. **Training Plans**: three plan cards, each expandable to show weekly schedule. Active plan shows a progress bar with auto-advance indicators.
3. **Workout — Ready Screen**: setup illustration showing phone placement (landscape, 2–3 feet away, leaning against an object), lighting tips, body visibility checklist, camera permission button, "I'm Ready" CTA.
4. **Workout — Stance Confirmation**: camera preview with overlay showing green/red checkmarks for each calibration check (body detected, landmarks visible, distance OK, position OK). Real-time coaching prompts guide the user. 3-second countdown when all checks pass.
5. **Workout — Active Tracking** (landscape): full-screen camera preview, skeleton/landmark overlay, large rep counter (centered, ≥ 72pt, readable from floor), live form hint text, "End Set" button. Pause overlay if user leaves frame.
6. **Workout — Rest Period**: countdown timer (large), set summary (reps completed), "Skip Rest" / "Next Set" buttons.
7. **Workout — Summary**: total reps, sets, duration, form score (0–100) with 3 sub-scores (depth, alignment, consistency), ranked improvement list, "Done" button.
8. **AI Coach**: chat bubbles, suggested prompt chips, premium lock overlay for free users.
9. **Paywall Modal**: feature list, pricing cards (monthly $4.99 / yearly $19.99), animated entry from bottom.
10. **Profile**: stats grid, plan progress, session history list.
11. **Form Guide**: categorized tips with images.

### Orientation strategy

- **Workout screens** (Ready, Stance Confirmation, Active Tracking, Rest): **landscape only**. Landscape gives a wider field of view that better captures the user's shoulder span and arm positions. The phone is on the floor in front of the user, so landscape is the natural orientation.
- **All other screens** (Home, Plans, AI Coach, Profile, Form Guide, Paywall): **portrait** (standard iOS UX).
- The app handles the orientation transition smoothly when entering/exiting a workout.

### UX for workout screen (readability from pushup position)

- The rep counter must be **very large** (≥ 72pt equivalent) and high-contrast (coral on dark, or white on dark).
- Live form hints should be **short** (3–5 words max, e.g., "Good depth" / "Go lower") and positioned where the user's eyes naturally fall (near the rep counter).
- Skeleton overlay should be **subtle** (thin lines, semi-transparent) so it doesn't distract.
- The "End Set" button should be **large and accessible** but not in a position where it's accidentally tapped.

---

## 7. Technical Considerations

### 7.1 Pose Estimation: Model Selection & Switching Architecture

Based on benchmarking research (2025–2026 data):

| Model | Landmarks | mAP (fitness poses) | Bundle size | Integration |
|-------|-----------|---------------------|-------------|-------------|
| **MediaPipe BlazePose** | 33 (2D + 3D) | ~45.0 | ~5–10 MB CoreML model | CoreML or TFLite delegate |
| **Apple Vision** | 19 (2D) | ~32.8 | 0 (built into iOS) | Native `VNDetectHumanBodyPoseRequest` |
| MoveNet Thunder | 17 (2D) | Comparable to BlazePose | ~10 MB TFLite model | TFLite only |

**Decision: MediaPipe BlazePose is the primary model.** Reasons:

- 33 landmarks vs. 19 (more data points for form scoring, especially shoulder symmetry and elbow tracking from front angle).
- Higher accuracy on fitness-related poses (~45 mAP vs ~33 mAP).
- Proven in production for pushup/fitness use cases (widely used in fitness apps).
- 3D landmark support enables potential future depth estimation improvements.

**Apple Vision is the fallback.** Reasons:

- Zero bundle size (already on the device).
- Fastest integration path.
- Sufficient for basic rep counting (vertical head displacement), even if form scoring is less granular.

**Switching architecture (protocol-based):**

The pose detection layer is abstracted behind a Swift protocol so switching between models is a one-line configuration change:

```swift
protocol PoseProvider {
    func detectPose(in frame: CMSampleBuffer) async -> PoseResult?
}

struct PoseResult {
    let landmarks: [LandmarkType: CGPoint]  // Normalized 0–1 coordinates
    let confidence: Float
    let timestamp: TimeInterval
}

// Two conforming implementations:
class MediaPipePoseProvider: PoseProvider { ... }
class AppleVisionPoseProvider: PoseProvider { ... }
```

At app startup, the active provider is selected based on configuration. This makes A/B testing and benchmarking trivial during Phase 0.

### 7.2 Recommended Phone Distance & Calibration

Based on front selfie camera characteristics (iPhone 12+ wide-angle selfie lens):

- **Recommended distance: 2–3 feet (60–90 cm)** from phone to user's head.
- At this distance, the selfie camera captures head + shoulders + upper arms comfortably.
- The calibration screen validates distance by checking that the **shoulder span occupies 30–60% of the frame width**. Too large = too close. Too small = too far.
- The Ready Screen shows a clear illustration of the recommended setup: phone on the floor, landscape orientation, leaning against a water bottle or shoe, ~2–3 feet in front of the user's head.

### 7.3 Rep Counting from the Front Angle

From a front-facing camera, the most reliable signals for pushup counting are:

- **Vertical displacement of the nose/head landmark**: goes down in "down" phase, comes back up in "up" phase.
- **Shoulder-to-camera apparent size**: shoulders appear larger (closer) in the down phase.
- **Elbow angle changes**: elbows bend outward/inward as visible from the front.
- **Relative distance between nose and shoulder landmarks**: decreases when the user is in the "down" position.

The counting state machine:

```
IDLE → (pose detected + calibration passed) → READY
READY → (downward movement exceeds threshold) → DOWN_PHASE
DOWN_PHASE → (upward movement exceeds threshold + minimum depth reached) → UP_PHASE → count += 1
UP_PHASE → (stable at top) → READY (waiting for next rep)

// Edge case: body leaves frame
ANY_TRACKING_STATE → (pose lost for > 0.5s) → PAUSED (show warning)
PAUSED → (pose re-detected + stable for ≥ 1s) → resume previous state
```

Hysteresis/smoothing:
- Require a landmark position to remain past a threshold for N consecutive frames (e.g., 3–5 frames at 10+ fps) before transitioning states.
- This prevents jitter, partial movements, and head-nodding from triggering false counts.

### 7.4 Form Scoring (Post-Set)

Computed from aggregated per-rep measurements:

| Sub-score | What it measures | How (front camera) |
|-----------|------------------|--------------------|
| **Depth (0–100)** | Did the user go low enough on each rep? | Track minimum nose/head Y-position per rep. Compare to calibration baseline. Penalize reps where depth is <70% of deepest rep. |
| **Alignment (0–100)** | Did the user stay level and symmetrical? | Compare left-shoulder vs right-shoulder Y-positions across frames. Penalize frames where asymmetry exceeds a threshold. Track head lateral drift. |
| **Consistency (0–100)** | Were reps uniform in tempo and range? | Compute standard deviation of: rep duration, depth reached, top-position height. Lower variance = higher score. |

**Composite score** = weighted average (40% depth + 30% alignment + 30% consistency), scaled to 0–100.

**Improvement suggestions** are generated from whichever sub-score is lowest + specific observations (e.g., "Your last 3 reps were shallower than your first 5 — try to maintain depth even when tired").

### 7.5 Backend Architecture (Full)

The app uses a **full-fledged backend** (not a lightweight proxy) to support user accounts, subscription validation, session sync, AI coach relay, and trial tracking.

**Recommended stack: Supabase** (hosted PostgreSQL + Auth + Edge Functions + Row Level Security).

| Backend component | Technology | Purpose |
|-------------------|------------|---------|
| **Authentication** | Supabase Auth (Sign in with Apple) | User identity, tied to Apple ID |
| **Database** | Supabase PostgreSQL | Session history, plan progress, streaks, subscription status, free-set counter |
| **API** | Supabase Edge Functions (Deno/TypeScript) | AI Coach proxy (holds OpenAI key), subscription receipt validation, business logic |
| **Row Level Security** | Supabase RLS policies | Users can only read/write their own data |
| **Realtime** | Supabase Realtime (optional, future) | Cross-device sync if needed later |

**Database tables (core):**

```sql
users (id, apple_id, created_at, subscription_status, subscription_expires_at, free_sets_used)
sessions (id, user_id, started_at, ended_at, total_reps, total_sets, duration_seconds, form_score, depth_score, alignment_score, consistency_score, avg_tempo, improvements_json)
plans (id, user_id, plan_type, current_week, current_day, started_at, completed_at)
streaks (id, user_id, current_streak, longest_streak, last_workout_date)
ai_conversations (id, user_id, messages_json, created_at)
```

**Why Supabase over alternatives:**
- Managed PostgreSQL (no server maintenance).
- Built-in Sign in with Apple support.
- Edge Functions can hold OpenAI API keys securely and relay requests.
- Row Level Security ensures data isolation without custom middleware.
- Scales well from MVP to production traffic.
- Lower ongoing cost than a custom backend.

### 7.6 AI Coach (OpenAI via Backend)

- The iOS app sends chat messages to a **Supabase Edge Function**.
- The Edge Function constructs a system prompt by querying the user's data (streak, plan progress, last 5 sessions), then forwards the request to the **OpenAI Chat Completions API** (GPT-4o or latest).
- The OpenAI API key is **only on the backend** (never in the app binary).
- **Cost management**: limit conversation length (e.g., 20 messages per session), compress/summarize older context.
- **Fallback**: if offline, the app attempts **Apple Foundation Models** (on-device, iOS 18.x+). Shows a "limited mode" notice. If neither is available, shows an offline message.

### 7.7 Subscription Validation

- Use **StoreKit 2** on-device for purchase flow.
- After purchase, the app sends the **App Store transaction** to the backend.
- The backend validates the receipt with Apple's App Store Server API and updates the user's `subscription_status` and `subscription_expires_at` in the database.
- On app launch, the app checks `Transaction.currentEntitlements` locally AND verifies with the backend.
- The free-set counter (`free_sets_used`) is stored server-side, tied to the Apple ID. This prevents bypass via reinstall.

### 7.8 Data Sync Strategy

- **Local-first**: the app writes session data to Core Data immediately. It works fully offline.
- **Background sync**: when the device has connectivity, the app syncs new/updated sessions to Supabase. Uses a `synced` boolean flag per record.
- **Conflict resolution**: server timestamp wins (last-write-wins). Acceptable for this use case since one user = one device in v1.

### 7.9 Minimum Device Requirements

- **iOS 16+** (for modern SwiftUI features + Vision framework maturity).
- **iPhone 12 or newer** recommended (for Neural Engine performance with MediaPipe CoreML model). Older devices fall back to Apple Vision at reduced accuracy.

### 7.10 Dependencies (External)

| Dependency | Purpose | Cost |
|------------|---------|------|
| MediaPipe BlazePose (CoreML) | Primary pose estimation | Free / open-source |
| Apple Vision framework | Fallback pose estimation | Free (built into iOS) |
| Supabase (hosted) | Backend: auth, database, edge functions | Free tier → Pro at $25/mo when scaling |
| OpenAI API | AI Coach chat | Pay-per-use (~$0.005–0.01 per conversation turn with GPT-4o) |
| StoreKit 2 | Subscriptions | Free (Apple takes 15–30% of revenue) |

---

## 8. Phase 0: Test Environment (Build First)

**Before building any UI or features, the first milestone is a test harness that validates the core technical assumptions.** This is a standalone Xcode project (or a build target within the main project) that proves:

### 8.0.1 What Phase 0 proves

| # | Test | Pass criteria |
|---|------|--------------|
| P0-1 | **Camera capture works** via front selfie camera in landscape | Live camera preview renders on screen |
| P0-2 | **MediaPipe BlazePose runs on-device** and returns landmarks | ≥ 10 fps inference, landmarks displayed as dots on the camera preview |
| P0-3 | **Apple Vision runs on-device** and returns landmarks | Same as above but with Apple Vision, to validate the fallback path |
| P0-4 | **PoseProvider protocol switching** works | Can toggle between MediaPipe and Apple Vision at runtime with one config change |
| P0-5 | **Landmark detection from front-facing pushup angle** is reliable | At 2–3 feet, with a person in pushup position, key landmarks (nose, shoulders, elbows, wrists) are detected with ≥ 0.7 confidence |
| P0-6 | **Calibration checks work**: body detected, landmarks visible, distance OK | The app can distinguish "in position" from "not in position" from "too close/far" |
| P0-7 | **Rep counting state machine works** | Correctly counts reps during a real pushup session (≥ 90% accuracy vs. manual count in 10+ test sessions) |
| P0-8 | **Counting is real-time** | Rep count updates on screen within 500 ms of completing a rep |
| P0-9 | **Pause/resume on frame exit** works | When user leaves frame, counting pauses. When they return, it resumes without losing the count. |
| P0-10 | **Form scoring produces reasonable sub-scores** | Depth, alignment, and consistency scores differentiate between intentionally good and intentionally bad form |

### 8.0.2 What Phase 0 looks like

A minimal app with:
- Full-screen camera preview (landscape, front camera).
- Landmark dots overlaid on the preview (colored by confidence level).
- A toggle switch to flip between MediaPipe and Apple Vision.
- A rep counter displayed on screen.
- A simple log/console output showing: detected landmarks, state machine transitions, per-rep measurements, and final form sub-scores.
- No styling, no navigation, no backend, no auth, no plans, no streaks. Pure technical validation.

### 8.0.3 Phase 0 success gate

Phase 0 is complete when all P0-1 through P0-10 pass. Only then does development proceed to Phase 1 (UI + features). If any test fails, the issue is investigated and resolved before moving on. In particular:
- If MediaPipe accuracy from front angle is insufficient → investigate MoveNet Thunder or model fine-tuning.
- If front-camera pushup detection is fundamentally unreliable → reconsider camera angle strategy (this would be a major pivot, so Phase 0 catches it early and cheaply).

---

## 9. Implementation Phases (Post Phase 0)

| Phase | Scope | Depends on |
|-------|-------|------------|
| **Phase 0** | Test environment: camera + pose + counting + scoring validation | Nothing |
| **Phase 1** | Workout flow: Ready Screen → Calibration → Active Tracking → Rest → Summary | Phase 0 |
| **Phase 2** | Backend + Auth: Supabase setup, Sign in with Apple, session sync, free-set tracking | Phase 0 |
| **Phase 3** | Home Dashboard, Streaks, Profile | Phase 1 + 2 |
| **Phase 4** | Training Plans (static, auto-advance) | Phase 3 |
| **Phase 5** | Paywall + Subscription (StoreKit 2 + server validation) | Phase 2 |
| **Phase 6** | AI Coach (OpenAI via Edge Function, Apple on-device fallback) | Phase 2 + 5 |
| **Phase 7** | Form Guide, polish, animations, haptics | Phase 1 |
| **Phase 8** | QA, beta testing, App Store submission | All |

---

## 10. Success Metrics

| Metric | Target | How to measure |
|--------|--------|----------------|
| Rep counting accuracy | ≥ 95% match vs. manual count on test sessions | Internal QA: compare app count to video-reviewed count |
| Rep count latency | < 500 ms from rep completion to screen update | Instrument the pose → state-machine → UI pipeline |
| Form score correlation | ≥ 80% agreement with expert manual review | Have a trainer score 50+ sessions, compare to app scores |
| Calibration completion rate | ≥ 90% of first-time users pass calibration | Analytics event: calibration_started vs. calibration_completed |
| Day-7 retention | ≥ 30% | Users who open the app on day 7 after install |
| Streak engagement | ≥ 40% of weekly-active users have a 7+ day streak | Local analytics / in-app tracking |
| Free → paid conversion | ≥ 8% within 30 days of install | StoreKit transaction data + backend metrics |
| AI Coach usage (premium) | ≥ 3 conversations/week per premium user | Backend analytics |

---

## 11. Resolved Questions (Previously Open)

| # | Question | Resolution |
|---|----------|------------|
| OQ-1 | Pose model choice | **MediaPipe BlazePose primary**, Apple Vision fallback. Protocol-based switching makes it trivial to swap. Research shows BlazePose has higher accuracy (45 mAP vs 33 mAP) and more landmarks (33 vs 19) for fitness poses. |
| OQ-2 | Minimum phone distance | **2–3 feet (60–90 cm)**. Calibration screen instructs the user on placement and validates distance via landmark sizing (shoulder span = 30–60% of frame width). |
| OQ-3 | Free-set tracking | **Tied to Apple ID** via full-fledged Supabase backend. Server-side counter prevents reinstall bypass. |
| OQ-4 | Plan advancement | **Automatic**. Plans auto-advance when daily workout is completed. |
| OQ-5 | Exercises in plans | **Pure pushups only**. No warm-ups or other exercises. |
| OQ-6 | Calorie estimation | **Removed**. Too imprecise without biometrics. Not in v1. |
| OQ-7 | Orientation | **Landscape for workout screens** (wider FOV for shoulder/arm detection). **Portrait for all other screens** (standard iOS UX). |
| OQ-8 | User leaves frame | **Pause counting + show warning**. Resume automatically when user returns and is stable for ≥ 1 second. Count is preserved. |

---

*PRD version: 2.0*
*Last updated: March 18, 2026*
*Author: AI-assisted, based on product requirements from the founder*
