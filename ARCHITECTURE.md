# PushupCoach — Architecture Review

## Current App Structure

```
PushupCoach/                      (3,233 lines of Swift — ALL files flat, no subdirectories)
├── PushupCoachApp.swift                 10 LOC   App entry point
├── Phase0TestView.swift                752 LOC   ViewModel (345) + View (400) merged
├── PoseProvider.swift                  284 LOC   6 types in one file: enums, structs, protocol
├── RepCountingEngine.swift             346 LOC   Rep state machine + calibration
├── FeedbackEngine.swift                316 LOC   4 types + engine class
├── FormScoringEngine.swift             209 LOC   Post-workout scoring
├── FaceOrientationTestView.swift       196 LOC   ViewModel + View + mesh topology
├── CameraManager.swift                 163 LOC   AVCaptureSession wrapper
├── PoseTrackingGate.swift              135 LOC   Tracking lock/unlock FSM
├── MediaPipePoseProvider.swift         125 LOC   BlazePose pose provider
├── CameraPreviewView.swift             107 LOC   UIViewRepresentable + UIView
├── LandmarkOverlayView.swift            85 LOC   Skeleton overlay
├── VisionOrientation.swift              81 LOC   Coordinate transforms
├── AppleVisionPoseProvider.swift        79 LOC   Apple Vision pose provider
├── FaceDebugCameraManager.swift         78 LOC   Face-only camera session
├── DepthBarView.swift                   56 LOC   Depth bar UI component
├── MediaPipeFaceDebugProvider.swift     55 LOC   Face landmarker wrapper
├── CoachingOverlayViews.swift           55 LOC   Shoulder level HUD
├── LandmarkSmoother.swift               35 LOC   EMA smoothing
├── PushupPoseConstants.swift            32 LOC   Shared thresholds
├── WorkoutOrientationLock.swift         10 LOC   Empty placeholder
├── Info.plist
├── Assets.xcassets/
└── Models/                              ML model files (.task)
```

**Tech stack:** Swift 5 · iOS 17+ · SwiftUI · AVFoundation · MediaPipe (SwiftTasksVision SPM) · MVVM

---

## Issues Found

### 1. God File — `Phase0TestView.swift` (752 lines)

The single largest file contains **both** the ViewModel (22 `@Published` properties, ~345 lines) and the View (~400 lines). The ViewModel orchestrates camera lifecycle, pose processing, FPS tracking, coordinate mapping, and all engine dispatch. This violates single-responsibility and makes the file hard to navigate, review, or test.

**Recommendation:** Extract `Phase0ViewModel` into its own file. Further decompose the ViewModel's responsibilities (see issue #4).

### 2. Flat Directory Structure — Zero Organization

All 22 Swift source files live in a single directory with no grouping. There is no separation by feature, architectural layer, or concern. As the app grows beyond Phase 0, this becomes unmanageable.

**Recommended structure:**

```
PushupCoach/
├── App/
│   └── PushupCoachApp.swift
├── Models/
│   ├── Landmark.swift              (LandmarkType, Landmark, Landmark3D)
│   ├── PoseResult.swift            (PoseResult — data only)
│   ├── PoseResult+Analysis.swift   (computed properties for pose quality)
│   └── FormScores.swift
├── Engines/
│   ├── RepCountingEngine.swift
│   ├── FormScoringEngine.swift
│   ├── FeedbackEngine.swift
│   ├── PoseTrackingGate.swift
│   └── LandmarkSmoother.swift
├── Providers/
│   ├── PoseProvider.swift          (protocol only)
│   ├── MediaPipePoseProvider.swift
│   ├── AppleVisionPoseProvider.swift
│   ├── MediaPipeFaceDebugProvider.swift
│   └── FaceDebugCameraManager.swift
├── Camera/
│   ├── CameraManager.swift
│   ├── CameraPreviewView.swift
│   ├── CapturePortraitConfiguration.swift
│   └── VisionOrientation.swift
├── Workout/
│   ├── WorkoutViewModel.swift      (extracted from Phase0TestView)
│   ├── WorkoutView.swift
│   ├── WorkoutStartView.swift
│   ├── WorkoutCameraView.swift
│   └── WorkoutScoresView.swift
├── FaceTest/
│   ├── FaceOrientationViewModel.swift
│   └── FaceOrientationTestView.swift
├── Components/
│   ├── LandmarkOverlayView.swift
│   ├── DepthBarView.swift
│   ├── ShoulderLevelHUDView.swift
│   └── CoachingStripView.swift
├── Theme/
│   └── AppTheme.swift              (colors, button styles)
├── Constants/
│   └── PushupPoseConstants.swift
└── Resources/
    ├── Assets.xcassets/
    ├── Models/                      (.task files)
    └── Info.plist
```

### 3. `PoseProvider.swift` — Six Types Crammed Into One File (284 lines)

This file defines `LandmarkType` (enum, 52 cases), `Landmark`, `Landmark3D`, `PoseResult` (with ~30 computed properties), `PoseProviderType`, and the `PoseProvider` protocol. It mixes data models, business logic (pose quality assessment), and the provider abstraction in a single file.

**Recommendation:** Split into:
- `Landmark.swift` — `LandmarkType`, `Landmark`, `Landmark3D`
- `PoseResult.swift` — struct with basic data
- `PoseResult+Analysis.swift` — computed properties for quality, calibration, distance, etc.
- `PoseProvider.swift` — protocol + `PoseProviderType` enum only

### 4. ViewModel Has Too Many Responsibilities

`Phase0ViewModel` directly manages:
- Camera lifecycle (start/stop/configure)
- Pose detection pipeline orchestration
- FPS calculation
- Coordinate mapping (`mapToOverlay`)
- Engine dispatch (rep, form, feedback, tracking, smoothing)
- 22 `@Published` UI state properties
- Coaching text derivation
- Debug logging

This is a "God ViewModel" anti-pattern.

**Recommendation:**
- Extract a `PoseProcessingPipeline` class that owns `CameraManager`, `PoseProvider`, `LandmarkSmoother`, and `PoseTrackingGate`. It takes raw frames and produces processed, tracked poses.
- Extract an `FPSTracker` utility.
- Extract `LandmarkMapper` for the overlay coordinate conversion.
- The ViewModel should only wire the pipeline to SwiftUI state.

### 5. No Dependency Injection — Untestable

Every dependency in `Phase0ViewModel` is created internally:

```swift
let cameraManager = CameraManager()
private let repEngine = RepCountingEngine()
private let formEngine = FormScoringEngine()
private let smoother = LandmarkSmoother(alpha: 0.28)
private let trackingGate = PoseTrackingGate()
private let feedbackEngine = FeedbackEngine()
```

There are no protocols for the engines. Nothing can be mocked. Unit testing the ViewModel or any engine integration is effectively impossible.

**Recommendation:**
- Define protocols (or at minimum, accept engines via `init` parameters).
- Inject dependencies through the initializer.
- This also enables swapping implementations for different exercise types in the future.

### 6. No Test Target

There is no test target in the Xcode project. The engines (`RepCountingEngine`, `FormScoringEngine`, `FeedbackEngine`, `PoseTrackingGate`, `LandmarkSmoother`) are pure logic with no UIKit/AVFoundation dependencies — they are trivially unit-testable but have zero coverage.

**Recommendation:** Add `PushupCoachTests` target. Start with the engines — they have clearly defined inputs (`PoseResult`) and outputs (`RepUpdate`, `FormScores`, `FeedbackResult`).

### 7. Hardcoded Colors — No Design System

The accent color `Color(red: 1.0, green: 0.42, blue: 0.42)` appears **10 times** across 4 files. The success green `Color(red: 0.3, green: 0.9, blue: 0.5)` appears in 3 files. Opacity values like `.white.opacity(0.85)` are scattered everywhere with slight variations.

**Recommendation:** Create an `AppTheme` (or use Asset Catalog named colors):

```swift
enum AppTheme {
    static let accent = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let success = Color(red: 0.3, green: 0.9, blue: 0.5)
    static let textSecondary = Color.white.opacity(0.85)
}
```

### 8. Magic Numbers Outside Constants File

While `PushupPoseConstants` centralizes some thresholds, many magic numbers live inline in engines:

- `RepCountingEngine`: `downThresholdFraction: 0.06`, `worldDownThreshold: 0.04`, `pauseFrameThreshold = 15`, `maxExpectedTravel = 0.15`, calibration logic thresholds
- `FeedbackEngine`: `0.08` hip sag threshold, `0.07` shoulder asymmetry, `130` degree knee angle, `0.035` world alignment max
- `FormScoringEngine`: `0.7` depth ratio, `0.05` alignment max acceptable
- `PoseTrackingGate`: `framesToLock = 10`, `framesToDrop = 30`, `noseStabilityMaxRange = 0.03`

**Recommendation:** Move all tunable thresholds into `PushupPoseConstants` (or a dedicated config struct per engine). This makes tuning centralized and transparent.

### 9. `FaceOrientationTestView.swift` — Same God-File Pattern (196 lines)

Contains `FaceOrientationViewModel`, `FaceOrientationTestView`, `FaceLandmarkCanvasView`, and `FaceMeshTopology` all in one file. Repeats the same structural problems as `Phase0TestView.swift`.

**Recommendation:** Split into separate files: `FaceOrientationViewModel.swift`, `FaceOrientationTestView.swift`, and `FaceMeshTopology.swift`.

### 10. Business Logic in Data Model (`PoseResult`)

`PoseResult` is a data struct, but it contains ~150 lines of computed properties that encode business rules: `isRepCountingQualityPose`, `isCalibratedForPushup`, `isPostureReadyForRepCounting`, `isPlankLikeForFaceOnCamera`, etc. These properties encode pushup-specific domain logic inside a generic pose data model.

**Recommendation:** Move these computed properties to an extension file (`PoseResult+PushupAnalysis.swift`) or extract a `PoseAnalyzer` class. This keeps `PoseResult` reusable if additional exercises are added.

### 11. Callback-Based Camera API Instead of Async/Await

`CameraManager` uses closure-based callbacks (`onPoseResult`, `onFrameProcessed`) and completion handlers. The ViewModel wraps these in `Task` blocks. With the iOS 17+ minimum deployment target, this could use `AsyncStream` for a cleaner data flow.

**Recommendation:**

```swift
// Instead of callbacks:
var poseStream: AsyncStream<PoseResult?> { ... }

// ViewModel consumes:
for await pose in cameraManager.poseStream {
    handlePoseSample(pose)
}
```

### 12. Thread Safety Risks

`CameraManager.onPoseResult` is set from the main actor but invoked from `processingQueue`. The callback immediately dispatches to `@MainActor`, but the closure capture itself (`[weak self]`) is not protected. The spin-wait loop in `stop()` (`Thread.sleep` in a while loop) is a code smell.

**Recommendation:** Use `AsyncStream` (see #11) or at minimum make the callbacks `@Sendable` and audit the capture semantics.

### 13. No Navigation Architecture

The app uses a single `ZStack` with `if/else` branches for view switching (`isRunning`, `formScores != nil`, else start view). This works for Phase 0 but won't scale.

**Recommendation:** Introduce a lightweight navigation state enum:

```swift
enum AppScreen {
    case start
    case workout
    case scores(FormScores)
    case faceTest
}
```

Use `NavigationStack` or a coordinator pattern as screens multiply.

### 14. Naming: "Phase0" Prefix

View and ViewModel are named `Phase0TestView` / `Phase0ViewModel`. The `Phase0` prefix is a development milestone label, not a user-facing concept. It will become confusing when Phase 1 arrives.

**Recommendation:** Rename to `WorkoutView` / `WorkoutViewModel` (or `SessionView` / `SessionViewModel`).

### 15. Empty/Placeholder Files

`WorkoutOrientationLock.swift` is a no-op placeholder (10 lines, does nothing). It exists only "to avoid removing from the Xcode project file."

**Recommendation:** Remove it. If orientation locking is needed later, add it then.

---

## Priority Summary

| Priority | Issue | Effort | Impact |
|----------|-------|--------|--------|
| **P0** | Extract ViewModel from Phase0TestView.swift | Low | Readability, reviewability |
| **P0** | Organize files into directories | Low | Navigation, onboarding |
| **P1** | Split PoseProvider.swift into focused files | Low | Maintainability |
| **P1** | Centralize hardcoded colors into AppTheme | Low | Consistency, rebrandability |
| **P1** | Move magic numbers into constants | Low-Med | Tunability |
| **P1** | Add unit test target for engines | Medium | Correctness, regression safety |
| **P2** | Dependency injection for ViewModel | Medium | Testability |
| **P2** | Extract PoseProcessingPipeline | Medium | Separation of concerns |
| **P2** | Move PoseResult business logic to extension | Low | Clean data model |
| **P2** | Modernize CameraManager to AsyncStream | Medium | Code clarity, thread safety |
| **P3** | Navigation architecture | Low-Med | Scalability |
| **P3** | Rename Phase0 → Workout | Low | Clarity |
| **P3** | Remove placeholder files | Trivial | Cleanliness |

---

## Key Takeaway

The core domain logic (rep counting, form scoring, feedback, tracking) is well-designed — clean state machines, layered evaluation, adaptive calibration. The problems are structural: everything lives in a flat directory, the ViewModel is a monolith, there's no test target, and shared values (colors, thresholds) are scattered. A focused restructuring pass — without changing any logic — would dramatically improve maintainability and set the codebase up for growth beyond Phase 0.
