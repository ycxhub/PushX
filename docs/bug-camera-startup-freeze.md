# Bug Fix: Camera Startup Freeze ("Starting camera..." stuck state)

**Date resolved:** March 2026
**Affected files:** `Phase0TestView.swift`, `CameraManager.swift`, `CameraPreviewView.swift`
**Severity:** Blocker — app was completely unusable after tapping Start Camera

---

## Symptom

Tapping **Start Camera** left the app stuck in a buffering state showing "Starting camera…". The UI either froze entirely (buttons unresponsive, Copy Logs untappable) or eventually transitioned to a dark screen with no camera preview. The startup spinner never cleared.

## Investigation Timeline

### Phase 1: Initial Inspection

Inspected the startup flow across `Phase0TestView.swift`, `CameraManager.swift`, `CameraPreviewView.swift`, `MediaPipePoseProvider.swift`, and the face-test control path in `FaceOrientationTestView.swift`. Identified that the startup spinner was controlled by `isStartingCamera`, which only cleared if the `configureAndStart` completion path ran. Proposed and approved a plan to add explicit startup phases, logging, and watchdogs.

### Phase 2: State Machine and Instrumentation

Implemented an explicit camera startup state machine (`CameraStartupPhase` enum: `.idle`, `.requestingPermission`, `.configuringSession`, `.running`, `.failed`), startup instrumentation via `addDebug()` calls, an 8-second startup watchdog timer, and debug UI in `Phase0TestView.swift`. Added queue-level milestone logging and single-fire completion handling in `CameraManager.swift`.

### Phase 3: Permission Red Herring

Early device testing showed the app freezing at "Requesting camera access…", with logs stopping after "Start requested". This led to multiple refactors of permission handling:

1. Moving permission resolution off the main actor
2. Using the callback API instead of `await AVCaptureDevice.requestAccess`
3. Polling `authorizationStatus` instead of relying on the async callback
4. Replacing Swift concurrency orchestration with plain GCD to eliminate task/actor scheduling as a variable

**None of these changes solved the freeze by themselves**, but they improved diagnostic visibility and proved that both permission resolution and session startup were actually succeeding.

### Phase 4: Diagnosis Shift — UI Transition Path

Device screenshots and logs showed the full successful pipeline:
- Camera permission was granted
- The `AVCaptureSession` was configured with the Front Camera
- `startRunning()` returned with `isRunning=true`
- Frames were being processed by the `captureOutput` delegate

But the visible UI still froze or went dark. This shifted the diagnosis from permission/session startup to the **UI transition path**.

Hypothesized that the preview transition itself might be freezing. Kept the app on the start screen during `.configuringSession` phase. Added a persistent debug banner and copyable log panel on the start screen, and later a runtime debug overlay on the camera screen.

### Phase 5: Root Cause Found

Deeper inspection of `Phase0TestView.swift` revealed the root cause: `setPreviewLayer(...)` was calling `objectWillChange.send()` from a callback ultimately driven by `CameraPreviewView`'s `layoutSubviews`.

This meant a **UIKit layout callback was force-invalidating SwiftUI during preview presentation**, creating a feedback loop exactly when the camera screen appeared. SwiftUI would re-render → trigger `CameraPreviewView` layout → which called `onLayerReady` → which called `setPreviewLayer` → which called `objectWillChange.send()` → which triggered SwiftUI to re-render → loop.

## Root Cause

**A SwiftUI/UIKit invalidation loop during preview-layer setup.**

`PreviewUIView.layoutSubviews()` fired `onLayerReady`, which called `Phase0ViewModel.setPreviewLayer(...)`, which called `objectWillChange.send()`. This invalidated the SwiftUI view graph, causing `CameraPreviewView` to update, which triggered another layout pass, creating an infinite re-render cycle that starved the main thread.

## Fix

1. Removed the manual `objectWillChange.send()` call from `setPreviewLayer(...)`
2. Guarded against redundant preview-layer assignments (only update if the layer actually changed)

## Verification

The final successful logs showed the full healthy startup path:

```
Camera permission granted
Selected provider: MediaPipe
Configuring capture session
startup: entered session queue
startup: committed configuration
startup: invoking completion before startRunning()
startup: calling startRunning()
startup: startRunning() returned (isRunning=true)
First frame processed — camera running
Waiting for landmarks, distance & plank angle
Calibrated — baseline noseY: 0.787
```

## Artifacts Retained

The debug logging infrastructure (startup state banner, debug log panel with Copy Logs, `addDebug()` instrumentation throughout the startup path) was intentionally kept in place for ongoing development work on calibration, landmark lock-on, and pose quality tuning.

## Lessons Learned

1. **SwiftUI + UIKit bridging is a common source of invalidation loops.** Any `UIViewRepresentable` that calls back into an `ObservableObject` from `layoutSubviews` or similar UIKit lifecycle methods can create feedback loops. Always guard against redundant updates.

2. **Frozen UI ≠ background thread problem.** The initial assumption was that the main thread was blocked by permission handling or AVFoundation session locking. The actual cause was an infinite re-render loop on the main thread — the thread wasn't blocked waiting on anything, it was busy re-rendering forever.

3. **Instrumentation before speculation.** The explicit state machine and debug logging were essential. Without them, the permission refactors would have continued indefinitely. The logs proved that permission and session startup were working, forcing the diagnosis to shift to the UI layer.

4. **Device Console.app vs Xcode debug console.** `print()` output does not appear in macOS Console.app for device builds — it only shows in Xcode's debug area when the app is launched from Xcode. System-level logs (AVFoundation, TCC) appear in Console.app but app-level `print()` does not. The in-app debug panel was the most reliable diagnostic channel for on-device testing without Xcode attached.
