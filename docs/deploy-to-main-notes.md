# Deploy to main notes

<!-- Entries appended by deploy-to-main workflow -->

## #1 — Camera startup reliability, lazy MediaPipe, rep baseline lock [High]

**Date & time (IST):** 22 Mar 2026, 10:29

**Deployment notes**

- **Bug fixes:** `CameraManager` completion before `startRunning()`, session-queue completion and single-finish guard; `MediaPipePoseProvider` lazy landmarker init off the main thread
- **Feature enhancements:** Phase 0 camera startup phases, permission flow with timeout, watchdog and debug log UI; rep engine requires a short stable plank streak before baseline lock
- **Docs:** `docs/bug-camera-startup-freeze.md`
- **Chore:** `.gitignore` includes `.env.local` (not committed)
- **GitHub:** pushed `main` (`787eb75`). **Vercel:** no `vercel.json` in repo (native iOS project); nothing to deploy on Vercel from this push

**3 files with largest changes (by lines changed)**

1. `PushupCoach/Phase0TestView.swift` — 563 lines (448 insertions, 115 deletions)
2. `docs/bug-camera-startup-freeze.md` — 93 lines (93 insertions)
3. `PushupCoach/CameraManager.swift` — 51 lines (43 insertions, 8 deletions)

_Complexity:_ combined `git show HEAD --numstat` before this note: 6 files, 632 insertions + 134 deletions → **High** (> 200 lines).

## #2 — Cursor slash commands and YCX agent rules [High]

**Date & time (IST):** 22 Mar 2026, 10:36

**Deployment notes**

- **Feature enhancements:** Slash commands `deploy-to-main`, `pull-from-main`, `give-sql-code`; agent rules `generate-tasks`, `task-list`, `research-latest-info` for PRD/task workflow
- **GitHub:** pushed `main` (`e0e4974`). **Vercel:** native iOS repo — no Vercel deploy from this push

**3 files with largest changes (by lines changed)**

1. `.cursor/rules/generate-tasks.mdc` — 79 lines (79 insertions)
2. `.cursor/commands/pull-from-main.md` — 46 lines (46 insertions)
3. `.cursor/rules/task-list.mdc` — 42 lines (42 insertions)

_Complexity:_ `git show e0e4974 --numstat`: 6 files, 230 insertions → **High** (> 200 lines).

## #3 — Rewrite pose geometry for phone-against-wall setup [High]

**Date & time (IST):** 22 Mar 2026, 17:59

**Deployment notes**

- **Bug fixes:** Replace plank detection heuristics (`isTrunkAngleReadyForPushup`, `isPlankLikeForFaceOnCamera`) with `isInPlankFromFrontCamera` and `isStandingPose` for correct phone-vertical-against-wall geometry; reject phantom reps via minimum depth gate; fix false-positive plank when standing
- **Feature enhancements:** Baseline lock increased 12→30 frames; down/up thresholds raised (0.06→0.10, 0.03→0.05); feedback engine shows context-aware messages for standing vs plank; Phase0TestView setup instructions updated for phone-against-wall portrait
- **New features:** SPM `Package.swift` for unit testing; `standingPose()` synthetic builder; plank detection + standing rejection unit tests (47 tests, 0 failures); Phase 0 on-device test protocol doc
- **Docs:** PRD v2.1 — fix all "potrait"/"landscape" typos, consistently describe phone placement as vertical against wall
- **GitHub:** pushed `main` (`7405c8f`). **Vercel:** native iOS project; nothing to deploy on Vercel

**3 files with largest changes (by lines changed)**

1. `docs/phase0-device-test-protocol.md` — 450 lines (450 insertions)
2. `Tests/EngineTests/RepCountingEngineTests.swift` — 274 lines (274 insertions)
3. `Tests/EngineTests/FormScoringEngineTests.swift` — 181 lines (181 insertions)

_Complexity:_ `git show 7405c8f --numstat`: 14 files, 1322 insertions + 71 deletions → **High** (> 200 lines).

## #4 — Multi-joint rep gates, ascending phase, phantom rep rejection [High]

**Date & time (IST):** 22 Mar 2026, 15:13

**Deployment notes**

- **Bug fixes:** Reject phantom reps from forward/backward sway (delta-relative gate), whole-body translation (wrist anchor gate), and impossibly fast reps (minimum duration 0.35s); ascending timeout (5s) prevents stuck state; suppress box/body-position feedback during active exercise
- **Feature enhancements:** New Ascending phase replaces instant Up→Ready with return-to-baseline confirmation (4 frames near baseline); phase-transition debounce increased 4→6 frames; safe frame inset widened 5%→2%; multi-joint diagnostic logging on lock, descent, ascent, rep count, and rejection
- **New features:** 9 new unit tests covering sway rejection, wrist drift, minimum duration, ascending phase confirmation, timeout, and diagnostic log format
- **Chore:** YCX A-Team slash commands (10), checklists (3), and engineering ethos rules
- **Docs:** Phase 0 device test protocol v2 with latest test observations; new rep-counting test protocol
- **GitHub:** pushed `main` (`82643a2`). **Vercel:** native iOS project; nothing to deploy on Vercel

**3 files with largest changes (by lines changed)**

1. `docs/phase0-device-test-protocol.md` — 482 lines (282 insertions, 200 deletions)
2. `docs/rep-counting-test-protocol.md` — 347 lines (347 insertions)
3. `PushupCoach/RepCountingEngine.swift` — 308 lines (249 insertions, 59 deletions)

_Complexity:_ `git show 82643a2 --numstat`: 22 files, 2546 insertions + 320 deletions → **High** (> 200 lines).

## #5 — Hip anchor gate, max duration gate, screen-space-only gates, session summary [High]

**Date & time (IST):** 22 Mar 2026, 15:59

**Deployment notes**

- **Bug fixes:** Hip anchor gate (drift >0.08 rejects kneeling/posture break); maximum rep duration gate (8s cap rejects stuck-in-DOWN artifacts); all gate decisions now screen-space only (world coords removed from descent, return, and depth gates — retained for display only); fix `.up`→`.ascending` enum in LandmarkOverlayView
- **Feature enhancements:** Session summary prepended to clipboard on Copy Logs (rep/rejection/timeout counts); debug log buffer 50→200 entries; frame counter + timestamp format `[F<frame> t<seconds>]`; near-miss diagnostic in Ready phase (throttled/60 frames); all log formatters include hip drift
- **New features:** 2 new unit tests — hip drift kneeling rejection, very long rep rejection
- **Docs:** Rep counting test protocol rewritten as single 5-phase comprehensive smoke test replacing 9 separate tests
- **GitHub:** pushed `main` (`5d8fc44`). **Vercel:** native iOS project; nothing to deploy on Vercel

**3 files with largest changes (by lines changed)**

1. `docs/rep-counting-test-protocol.md` — 373 lines (87 insertions, 286 deletions)
2. `PushupCoach/RepCountingEngine.swift` — 153 lines (93 insertions, 60 deletions)
3. `PushupCoach/Phase0TestView.swift` — 43 lines (39 insertions, 4 deletions)

_Complexity:_ `git show 5d8fc44 --numstat`: 5 files, 250 insertions + 351 deletions → **High** (> 200 lines).

## #6 — MVP B-lite: home dashboard, session history, SwiftData persistence, app icon [High]

**Date & time (IST):** 22 Mar 2026, 17:12

**Deployment notes**

- **New features:** HomeView dashboard with today's stats, streak counter, quick-start workout; HistoryView with session list grouped by date, search, and delete; SessionDetailView with rep-by-rep breakdown, form scores, share export; FormTrendChart for composite form score trends; SessionExporter for sharing session data; SwiftData persistence layer (PushupSession + PushupRepRecord models, SessionStore); app icon (1024px); privacy policy page (HTML + Vercel)
- **Feature enhancements:** PushupCoachApp root switched to HomeView with SwiftData ModelContainer (error recovery fallback); Phase0TestView saves session to SwiftData on complete, "Done" button dismisses to home, summary handles < 2 reps gracefully; app display name set to "PushX"
- **Tests:** RepMappingTests validates RepMeasurement → PushupRepRecord mapping
- **Docs:** App Store Connect setup guide, App Store description copy, archive & upload guide, MVP design doc, MVP engineering spec, MVP task list
- **GitHub:** merged `feature/mvp-blite` → `main` (`a93c243`). **Vercel:** privacy-policy page deployable via `privacy-policy/vercel.json`

**3 files with largest changes (by lines changed)**

1. `docs/designs/pushx-mvp-eng-spec.md` — 472 lines (472 insertions)
2. `PushupCoach/SessionDetailView.swift` — 230 lines (230 insertions)
3. `PushupCoach/HomeView.swift` — 175 lines (175 insertions)

_Complexity:_ `git show a93c243 --numstat`: 26 files, 2398 insertions + 59 deletions → **High** (> 200 lines).

## #7 — Neon Kinetic design system, UI refresh, app icon catalog fix [High]

**Date & time (IST):** 22 Mar 2026, 21:53

**Deployment notes**

- **New features:** `DesignSystem.swift` — Neon Kinetic palette (`nk*` colors), kinetic gradients, typography scale, reusable modifiers; `docs/stitch_rest_timer/` Stitch exports (home, setup, active set, summary) + `neon_kinetic/DESIGN.md`
- **Feature enhancements:** HomeView, HistoryView, SessionDetailView restyled; Phase0TestView workout UI aligned with design system; FormTrendChart, DepthBarView, CoachingOverlayViews use design tokens
- **Bug fixes / chore:** App icon assets moved from `AppIcon 1.appiconset` → `AppIcon.appiconset` (matches Xcode `AppIcon` name); `DesignSystem.swift` added to Xcode target; `privacy-policy/.gitignore` ignores `.vercel`
- **GitHub:** pushed `main` (`896d6b8`). **Vercel:** native iOS + optional privacy-policy deploy unchanged

**3 files with largest changes (by lines changed)**

1. `PushupCoach/Phase0TestView.swift` — 838 lines (490 insertions, 348 deletions)
2. `PushupCoach/HomeView.swift` — 483 lines (362 insertions, 121 deletions)
3. `PushupCoach/SessionDetailView.swift` — 414 lines (285 insertions, 129 deletions)

_Complexity:_ `git show 896d6b8 --numstat`: 23 files, 2545 insertions + 707 deletions → **High** (> 200 lines).

## #8 — App Store prep, privacy manifest, production bundle ID, review UI fixes [High]

**Date & time (IST):** 23 Mar 2026, 12:02

**Deployment notes**

- **Bug fixes / polish:** Complete Neon Kinetic migration (remaining coral → `nk*` tokens); code review fixes (session start reactivity, swipe delete, force unwraps); review feedback (delete affordances, reset, debug log persistence, progress bar)
- **New features:** `PrivacyInfo.xcprivacy` privacy manifest bundled in app; `privacy-policy/pushx/` privacy + support pages; `docs/app-store/` encryption export compliance (HTML + MD), promotional summary
- **Feature enhancements:** `MARKETING_VERSION` 1.0, `PRODUCT_BUNDLE_IDENTIFIER` `com.pushx.app`, iPhone-only (`TARGETED_DEVICE_FAMILY` = 1); `ITSAppUsesNonExemptEncryption` false; shell script build phase patches MediaPipeTasksVision framework `Info.plist` for store validation; Xcode target display name **PushX**; `#if DEBUG` gates on face-orientation test, debug panel, provider switch, session debug log section
- **GitHub:** pushed `main` (`8ae9ab5` → `f014630`, 4 commits). **Vercel:** deploy `privacy-policy/pushx/` as needed for App Store URLs

**3 files with largest changes (by lines changed)** _(range `8ae9ab5..f014630`)_

1. `privacy-policy/pushx/index.html` — 375 lines (375 insertions)
2. `privacy-policy/pushx/support/index.html` — 104 lines (104 insertions)
3. `docs/app-store/Encryption_Export_Compliance_PushX.html` — 82 lines (82 insertions)

_Complexity:_ `git diff 8ae9ab5 f014630 --numstat`: 19 files, 841 insertions + 101 deletions → **High** (> 200 lines).

## #9 — Marketing page copy overhaul — design-system placeholders → PushX product copy [Medium]

**Date & time (IST):** 23 Mar 2026, 12:33

**Deployment notes**

- **Feature enhancements:** Replace all design-system placeholder copy (Neon Kinetic, Diamond Kinetics, Hypertrophy Block, Calibration, etc.) with product-relevant PushX messaging — emotional ("Train alone, train right", "Your phone watches. Your form improves.") and rational (on-device AI, form scoring, privacy-first)
- **Bug fixes:** Header icon replaced with actual PushX app icon (was external Google placeholder); favicon and apple-touch-icon added; "PUSHX" → "PushX" branding; Landscape → Portrait mode (matches actual app); page title and meta description updated for SEO
- **Assets:** `pushx-app-icon-1024.png` added to `privacy-policy/pushx/` for web use
- **GitHub:** pushed `main` (`b7ec597`). **Vercel:** deploy `privacy-policy/pushx/` for updated marketing page

**3 files with largest changes (by lines changed)**

1. `privacy-policy/pushx/index.html` — 81 lines (47 insertions, 34 deletions)
2. `privacy-policy/pushx/pushx-app-icon-1024.png` — binary (new file)

_Complexity:_ `git show b7ec597 --numstat`: 2 files, 47 insertions + 34 deletions → **Medium** (50–200 lines AND < 10 files).

## #10 — Launch assets, app flow upgrades, and archive signing hardening [High]

**Date & time (IST):** 26 Mar 2026, 20:57

**Deployment notes**

- **New features:** launch background/icon/splash asset sets + image binaries; richer persisted session data model (`PushupSessionModel`); archive fix helper script for vendor framework plist/dSYM/codesign handling
- **Feature enhancements:** substantial UX and state-flow updates across `PushXApp`, `HomeView`, `SessionDetailView`, `HistoryView`, and `Phase0TestView`; design system and form-scoring refinements
- **Bug fixes:** improved session/form handling reliability and archive-time framework metadata/signing hardening to reduce App Store validation/symbol upload issues
- **GitHub:** pushed `main` (`597084d`). **Vercel:** native iOS project; nothing to deploy on Vercel from this push

**3 files with largest changes (by lines changed)**

1. `PushupCoach/Phase0TestView.swift` — 233 lines (167 insertions, 66 deletions)
2. `PushupCoach/PushXApp.swift` — 189 lines (188 insertions, 1 deletion)
3. `PushupCoach/PushupSessionModel.swift` — 99 lines (99 insertions)

_Complexity:_ `git show HEAD --numstat`: 19 files, 894 insertions + 126 deletions → **High** (> 200 lines).
