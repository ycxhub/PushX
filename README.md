# PushX

PushX is an AI-led pushup tracking iOS app that sits on the floor in front of you, watches you with the selfie camera, and counts every pushup in real time while grading your form, all on your device, so you can train without a spotter and without logging reps by hand.

## MediaPipe BlazePose model variant

The app bundles **`pose_landmarker_full.task`** (BlazePose full) as the default: a practical balance of accuracy and on-device performance for fitness poses.

Google’s MediaPipe Tasks for iOS also ships **lite** and **heavy** variants (and sometimes GPU-focused builds). To switch:

1. Add the chosen `.task` file to `PushupCoach/Models/` and include it in **Copy Bundle Resources**.
2. In `MediaPipePoseProvider.setupLandmarker()`, set `path(forResource:ofType:)` to the new base name (e.g. `pose_landmarker_lite`).
3. Rebuild and profile FPS on your target devices.

Apple Vision remains available as a fallback provider from the in-app toggle.
