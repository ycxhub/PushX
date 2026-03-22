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
