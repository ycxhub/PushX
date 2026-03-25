# PushX 1.0.1 Hotfix Release Prep

Version: `1.0.1`
Build: `2`

## Release Goal

Stabilize on-device rep counting, startup reliability, diagnostics capture, and workout-screen clarity without changing the core product flow.

## Release Highlights

- Improved rep counting recovery when the first clean lock is missed.
- Reduced brittle dependence on head pose during plank and first rep detection.
- Added stronger camera startup and retry diagnostics.
- Added structured session diagnostics, including zero-rep sessions.
- Improved workout-screen readability and clarified action buttons.
- Replaced user-facing `MediaPipe` naming with `PushXPose`.
- Fixed Training Log session navigation loop.

## Must-Pass QA Before Submission

- Cold launch camera start succeeds on the release test device.
- Permission already granted path succeeds.
- Permission denied then re-enabled in Settings succeeds.
- `Try Again` meaningfully retries camera startup after a failure.
- A normal 5-10 rep set counts visibly on screen.
- First rep counts when the user looks toward the phone.
- Slightly imperfect framing still counts real reps.
- A zero-rep session still saves usable diagnostics.
- Training Log opens Session Detail directly and does not loop.
- `Begin Calibration` is visible in the first fold on the target device.

## Release Risks To Recheck

- False positives from forward/backward body motion or shoulder shake.
- Bootstrap starting from noisy landmarks on the first rep.
- Timeout recovery after a bad first attempt.
- Prompt mismatch after lock, especially `Get down into push-up position`.

## App Store Connect Notes

- Treat this as a hotfix release, not a feature release.
- Keep release notes focused on reliability and workout tracking quality.
- If false positives are still reproducible on the release device, hold submission and do one more rep-engine pass before uploading.

## Suggested Release Notes

PushX 1.0.1 improves workout tracking reliability, camera startup resilience, and session diagnostics. This update also sharpens calibration UX, clarifies workout controls, and fixes Training Log navigation.
