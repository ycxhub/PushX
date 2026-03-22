## Relevant Files

- `PushupCoach/PushupSessionModel.swift` - SwiftData model for workout sessions
- `PushupCoach/PushupRepRecordModel.swift` - SwiftData model for per-rep summary statistics (includes RepMeasurement mapping)
- `PushupCoach/SessionStore.swift` - SwiftData CRUD operations (save, fetch, delete, assemble)
- `PushupCoach/SessionExporter.swift` - JSON export for LLM consumption (single + multi-session)
- `PushupCoach/HomeView.swift` - App root view with start button, last session card, history link
- `PushupCoach/HistoryView.swift` - Session history list with form trend chart and export all
- `PushupCoach/SessionDetailView.swift` - Single session detail with per-rep breakdown and AI coach export
- `PushupCoach/FormTrendChart.swift` - Swift Charts line chart for composite score trend
- `PushupCoach/PushupCoachApp.swift` - Modified: ModelContainer + HomeView as root
- `PushupCoach/Phase0TestView.swift` - Modified: session save on stop, summary with Done button, dismiss flow
- `Tests/EngineTests/RepMappingTests.swift` - Unit tests for rep measurement mapping logic
- `Package.swift` - Unchanged (engine tests only; SwiftData tests require Xcode test target)

### Notes

- SwiftData requires iOS 17.0 — deployment target was already 17.0.
- Swift Charts requires iOS 16.0+ (covered by iOS 17 target).
- Use `swift test` from the package root to run EngineTests (66 tests).
- SwiftData round-trip tests (SessionStore, SessionExporter with real models) require an Xcode test target — deferred to App Store prep phase.

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

## Tasks

- [x] 0.0 Create feature branch
  - [x] 0.1 Create and checkout `feature/mvp-blite`

- [x] 1.0 SwiftData models and persistence layer
  - [x] 1.1 Created `PushupSessionModel.swift` — @Model with all fields, cascade relationship, computed properties
  - [x] 1.2 Created `PushupRepRecordModel.swift` — @Model with convenience init(from: RepMeasurement) mapping
  - [x] 1.3 Created `SessionStore.swift` — save, fetchAll, fetchRecent, delete, assemble. All with do/catch + os.Logger
  - [x] 1.4 Updated `PushupCoachApp.swift` — ModelContainer with crash-safe init fallback
  - [x] 1.5 Build verified, 59 existing tests pass

- [x] 2.0 RepMeasurement → PushupRepRecord mapping and session assembly
  - [x] 2.1 `PushupRepRecord.init(from:repNumber:)` computes depthScreenSpace, depthWorldMeters, shoulderAsymmetry, shoulderAsymmetryWorld
  - [x] 2.2 `SessionStore.assemble()` maps engine outputs → PushupSession + PushupRepRecord array
  - [x] 2.3 Edge cases handled: 0 reps, 1 rep (nil scores), empty shoulder arrays (asymmetry = 0.0)

- [x] 3.0 Wire session save into workout flow
  - [x] 3.1 Added @Environment(\.modelContext) and @Environment(\.dismiss) to Phase0TestView
  - [x] 3.2 Added sessionStartTime to Phase0ViewModel, set on startCamera()
  - [x] 3.3 stopCamera() now calls SessionStore.assemble() and publishes completedSession
  - [x] 3.4 .onChange saves session to SwiftData via SessionStore.save()
  - [x] 3.5 Summary view reads from completedSession (same data as persisted)
  - [x] 3.6 <2 reps case: session saved with nil scores, "Not enough reps" shown
  - [x] 3.7 "Done" button dismisses back to HomeView, "New Session" resets in-place

- [x] 4.0 Navigation and HomeView
  - [x] 4.1 Created HomeView with NavigationStack, PushX branding, start button, history link
  - [x] 4.2 Last session card with rep count, composite score, date
  - [x] 4.3 Lifetime stats row (total sets, total reps, avg form score)
  - [x] 4.4 PushupCoachApp root changed to HomeView()
  - [x] 4.5 Dark theme with coral accent, setup tips
  - [x] 4.6 fullScreenCover for workout, dismiss returns to Home

- [x] 5.0 History view with session list and form trend chart
  - [x] 5.1 HistoryView with @Query reverse-chronological
  - [x] 5.2 Session rows: date, rep count, composite score (colored), provider badge
  - [x] 5.3 Empty state with icon and message
  - [x] 5.4 FormTrendChart using Swift Charts — coral line + dots, 0-100 y-axis
  - [x] 5.5 Chart embedded at top of history, shown when ≥2 scored sessions
  - [x] 5.6 NavigationLink to SessionDetailView via session ID
  - [x] 5.7 Swipe-to-delete wired to SessionStore.delete()

- [x] 6.0 Session detail view with per-rep breakdown
  - [x] 6.1 SessionDetailView accepts PushupSession
  - [x] 6.2 Header: date, duration, rep count, provider, avg rep duration
  - [x] 6.3 Score card with composite, depth, alignment, consistency (colored)
  - [x] 6.4 Improvement suggestions list
  - [x] 6.5 Per-rep breakdown: number, duration, depth bar (relative), asymmetry warning
  - [x] 6.6 "Copy for AI Coach" button → SessionExporter → clipboard with toast
  - [x] 6.7 Nil scores handled: "Not enough reps for scoring" message

- [x] 7.0 LLM-compatible session export (SessionExporter)
  - [x] 7.1 SessionExporter.swift created in PushupCoach/ (flat structure)
  - [x] 7.2 toJSON(session:) — single session with metadata, scores, improvements, per-rep array
  - [x] 7.3 toJSON(sessions:) — multi-session with summary stats (totals, averages, composite trend)
  - [x] 7.4 JSONSerialization with prettyPrinted + sortedKeys. Graceful error fallback.
  - [x] 7.5 Wired in SessionDetailView "Copy for AI Coach" button
  - [x] 7.6 Wired in HistoryView "Export All for AI Coach" button with toast

- [x] 8.0 Unit tests for persistence, mapping, and export
  - [x] 8.1 RepMappingTests.swift in Tests/EngineTests/ (7 tests: depth, world depth, asymmetry, edge cases)
  - [x] 8.2 All 66 tests pass (59 existing + 7 new)
  - [x] 8.3 SwiftData round-trip tests (SessionStore, SessionExporter with real models) deferred to Xcode test target
  - [x] 8.4 Existing EngineTests confirm zero regressions

- [ ] 9.0 App Store preparation and submission
  - [x] 9.1 App icon generated: `docs/pushx-app-icon-1024.png` — glowing cyan X on dark background
  - [x] 9.2 App Store description written: `docs/app-store-description.md`
  - [x] 9.3 Privacy policy created: `privacy-policy/index.html` — deploy to hard75.com/pushx/privacy-policy via Vercel
  - [x] 9.4 App Store Connect setup guide: `docs/app-store-connect-setup.md`
  - [x] 9.5 Archive + upload guide: `docs/archive-and-upload.md`
  - [ ] 9.6 MANUAL: Set app display name to "PushX" in Xcode → Target → General → Display Name
  - [ ] 9.7 MANUAL: Drag icon into Assets.xcassets → AppIcon
  - [ ] 9.8 MANUAL: Deploy privacy policy — `cd privacy-policy && npx vercel --prod`
  - [ ] 9.9 MANUAL: Create app in App Store Connect (follow guide)
  - [ ] 9.10 MANUAL: Take screenshots on device/simulator
  - [ ] 9.11 MANUAL: Archive, upload, and submit (follow guide)
  - [ ] 9.12 MANUAL: Share TestFlight public link with WhatsApp group
