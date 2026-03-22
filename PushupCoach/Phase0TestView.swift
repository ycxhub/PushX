import SwiftUI
import AVFoundation
import UIKit

enum CameraStartupPhase: Equatable {
    case idle
    case requestingPermission
    case configuringSession
    case running
    case failed
}

private enum CameraPermissionResolution {
    case authorized
    case denied
    case timedOut
}

private enum CameraPermissionOutcome {
    case alreadyAuthorized
    case grantedAfterPrompt
    case denied
    case timedOut
}

@MainActor
final class Phase0ViewModel: ObservableObject {
    @Published var repCount: Int = 0
    @Published var currentPhase: RepCountingEngine.Phase = .idle
    @Published var overlayLandmarks: [OverlayLandmark] = []
    @Published var showSkeleton: Bool = false
    @Published var trackingState: PoseTrackingState = .lost
    @Published var coachingBanner: String = ""
    @Published var fps: Double = 0
    /// Default pose backend for new sessions (`MediaPipe` = BlazePose task; lazy-loaded off the main thread).
    @Published var providerType: PoseProviderType = .mediaPipe
    @Published var formScores: FormScores?
    @Published var completedSession: PushupSession?
    @Published private(set) var cameraStartupPhase: CameraStartupPhase = .idle
    @Published var debugMessages: [String] = []
    @Published var latestNoseY: CGFloat = 0
    @Published var depthPercent: CGFloat = 0
    @Published var isCalibratedForPushup: Bool = false
    @Published var feedbackMessage: String = ""
    @Published var secondaryCoachingText: String = ""
    @Published var workoutStateSubtitle: String = ""
    @Published var shoulderImbalanceMetric: CGFloat = 0
    @Published var repAnimToken: Int = 0
    @Published var cameraErrorMessage: String?
    @Published var processedFrameCount: Int = 0

    @Published var bodyDetected: Bool = false
    @Published var landmarksVisible: Bool = false
    @Published var distanceOK: Bool = false

    let cameraManager = CameraManager()
    private let repEngine = RepCountingEngine()
    private let formEngine = FormScoringEngine()
    private let smoother = LandmarkSmoother(alpha: 0.28)
    private let trackingGate = PoseTrackingGate()
    private let feedbackEngine = FeedbackEngine()
    private var appleVisionProvider = AppleVisionPoseProvider()
    private var mediaPipeProvider: MediaPipePoseProvider?

    private var frameCount = 0
    private var fpsTimer: Date = .now

    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    /// Exposed so coaching overlays can align with preview metadata space.
    weak var previewLayerForCoaching: AVCaptureVideoPreviewLayer? { previewLayer }

    private var overlaySize: CGSize = UIScreen.main.bounds.size

    /// Most recent non-nil smoothed pose, kept to allow FeedbackEngine to run.
    private var latestSmoothedPose: PoseResult?

    private var lastRepCount: Int = 0
    private var startupAttemptID: UUID?
    private var startupWatchdogTask: Task<Void, Never>?
    private var sessionStartTime: Date?

    var captureSession: AVCaptureSession { cameraManager.session }
    var isStartingCamera: Bool {
        switch cameraStartupPhase {
        case .requestingPermission, .configuringSession:
            return true
        case .idle, .running, .failed:
            return false
        }
    }

    var isRunning: Bool {
        switch cameraStartupPhase {
        case .running:
            return true
        case .idle, .requestingPermission, .configuringSession, .failed:
            return false
        }
    }

    var startupStatusText: String {
        switch cameraStartupPhase {
        case .idle:
            return ""
        case .requestingPermission:
            return "Requesting camera access…"
        case .configuringSession:
            return "Starting camera…"
        case .running:
            return "Camera live"
        case .failed:
            return "Camera failed to start"
        }
    }

    var startupBannerText: String {
        switch cameraStartupPhase {
        case .idle:
            return "State: Idle"
        case .requestingPermission:
            return "State: Requesting camera access"
        case .configuringSession:
            return "State: Configuring capture session"
        case .running:
            return "State: Camera running"
        case .failed:
            return "State: Camera failed"
        }
    }

    var debugLogText: String {
        if debugMessages.isEmpty {
            return "No logs yet."
        }
        return debugMessages.joined(separator: "\n")
    }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer, overlaySize: CGSize) {
        if previewLayer !== layer {
            previewLayer = layer
        }
        self.overlaySize = overlaySize
    }

    func updateOverlayContainerSize(_ size: CGSize) {
        overlaySize = size
    }

    func startCamera() {
        cameraErrorMessage = nil
        guard !isStartingCamera, cameraStartupPhase != .running else { return }

        sessionStartTime = Date()
        completedSession = nil

        let attemptID = UUID()
        startupAttemptID = attemptID
        updateCameraStartupPhase(.requestingPermission, log: "Start requested")
        addDebug("Camera authorization status: \(Self.describeAuthorizationStatus(AVCaptureDevice.authorizationStatus(for: .video)))")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let permission = Self.resolveCameraPermissionBlocking(timeoutSeconds: 8)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.startupAttemptID == attemptID else { return }
                switch permission {
                case .alreadyAuthorized:
                    self.addDebug("Camera permission already authorized")
                    self.beginCaptureStartup(attemptID: attemptID)
                case .grantedAfterPrompt:
                    self.addDebug("Camera permission granted")
                    self.beginCaptureStartup(attemptID: attemptID)
                case .denied:
                    self.cameraErrorMessage = "Camera access is required to start a session. You can enable it in Settings → Privacy & Security → Camera."
                    self.addDebug("Camera permission denied")
                    self.updateCameraStartupPhase(.failed)
                    self.startupAttemptID = nil
                case .timedOut:
                    self.cameraErrorMessage = "Camera permission did not resolve in time. Please try again."
                    self.addDebug("Camera permission request timed out after 8 seconds")
                    self.updateCameraStartupPhase(.failed)
                    self.startupAttemptID = nil
                }
            }
        }
    }

    func stopCamera() {
        cancelStartupWatchdog()
        startupAttemptID = nil
        cameraManager.clearOutputCallbacks()
        cameraManager.onStartupEvent = nil
        updateCameraStartupPhase(.idle, log: "Stop requested")

        cameraManager.stop { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let scores: FormScores?
                if self.repEngine.completedReps.count >= 2 {
                    scores = self.formEngine.computeScores(from: self.repEngine.completedReps)
                    self.formScores = scores
                } else {
                    scores = nil
                }

                let session = SessionStore.assemble(
                    repMeasurements: self.repEngine.completedReps,
                    formScores: scores,
                    providerType: self.providerType,
                    startedAt: self.sessionStartTime ?? Date(),
                    endedAt: Date()
                )
                self.completedSession = session
                self.addDebug("Camera stopped. Reps: \(self.repCount)")
            }
        }
    }

    func resetSession() {
        repEngine.reset()
        smoother.reset()
        trackingGate.reset()
        feedbackEngine.reset()
        repCount = 0
        currentPhase = .idle
        overlayLandmarks = []
        showSkeleton = false
        trackingState = .lost
        coachingBanner = ""
        feedbackMessage = ""
        secondaryCoachingText = ""
        workoutStateSubtitle = ""
        shoulderImbalanceMetric = 0
        repAnimToken = 0
        lastRepCount = 0
        formScores = nil
        completedSession = nil
        sessionStartTime = nil
        debugMessages = []
        depthPercent = 0
        latestNoseY = 0
        processedFrameCount = 0
        bodyDetected = false
        landmarksVisible = false
        distanceOK = false
        isCalibratedForPushup = false
        latestSmoothedPose = nil
        addDebug("Session reset")
    }

    func copyDebugLogsToPasteboard() {
        let summary = generateSessionSummary()
        UIPasteboard.general.string = summary + "\n" + debugLogText
        addDebug("Debug logs copied to clipboard")
    }

    private func generateSessionSummary() -> String {
        let repLines = debugMessages.filter { $0.contains("REP #") }
        let downLines = debugMessages.filter { $0.contains("DOWN |") }
        let rejectedLines = debugMessages.filter { $0.contains("REJECTED") }
        let ascendingLines = debugMessages.filter { $0.contains("ASCENDING dur=") }
        let timeoutLines = debugMessages.filter { $0.contains("TIMEOUT") }
        let lockedLines = debugMessages.filter { $0.contains("LOCKED |") }

        var lines = [
            "=== SESSION SUMMARY ===",
            "Reps counted   : \(repLines.count)",
            "DOWN entries    : \(downLines.count)",
            "ASCENDING entries: \(ascendingLines.count)",
            "REJECTED        : \(rejectedLines.count)",
            "TIMEOUTS        : \(timeoutLines.count)",
            "Baseline locks  : \(lockedLines.count)",
            "Frames processed: \(processedFrameCount)",
        ]

        if !rejectedLines.isEmpty {
            lines.append("--- Rejection reasons ---")
            for line in rejectedLines {
                if let start = line.range(of: "REJECTED ("),
                   let end = line.range(of: ")", range: start.upperBound..<line.endIndex) {
                    let reason = line[start.upperBound..<end.lowerBound]
                    lines.append("  \(reason)")
                }
            }
        }

        lines.append("========================")
        return lines.joined(separator: "\n")
    }

    func switchProvider() {
        let nextType: PoseProviderType = (providerType == .appleVision) ? .mediaPipe : .appleVision

        Task { @MainActor in
            if nextType == .mediaPipe {
                if mediaPipeProvider == nil {
                    mediaPipeProvider = MediaPipePoseProvider()
                }
                cameraManager.switchProvider(mediaPipeProvider!)
            } else {
                cameraManager.switchProvider(appleVisionProvider)
            }

            providerType = nextType
            addDebug("Switched to \(providerType.rawValue)")
        }
    }

    private func handlePoseSample(_ raw: PoseResult?) {
        guard let raw else {
            let gate = trackingGate.update(pose: nil)
            trackingState = gate.state
            showSkeleton = false
            coachingBanner = gate.coachingMessage
            feedbackMessage = ""
            secondaryCoachingText = ""
            shoulderImbalanceMetric = 0
            bodyDetected = false
            landmarksVisible = false
            distanceOK = false
            isCalibratedForPushup = false
            overlayLandmarks = []

            let update = repEngine.update(with: nil)
            currentPhase = update.phase
            repCount = update.repCount
            if let ny = update.noseY { latestNoseY = ny }
            depthPercent = update.depthPercent ?? repEngine.continuousDepthPercent(pose: nil)
            if let msg = update.debugMessage { addDebug(msg) }
            refreshWorkoutSubtitle()
            bumpRepAnimationIfNeeded(newCount: update.repCount)
            return
        }

        let smoothed = PoseResult(
            landmarks: smoother.smooth(landmarks: raw.landmarks),
            worldLandmarks: raw.worldLandmarks,
            timestamp: raw.timestamp
        )
        latestSmoothedPose = smoothed
        let gate = trackingGate.update(pose: smoothed)
        trackingState = gate.state

        switch gate.state {
        case .lost:
            coachingBanner = gate.coachingMessage
            feedbackMessage = ""
            secondaryCoachingText = ""
            shoulderImbalanceMetric = 0
            bodyDetected = false
            landmarksVisible = false
            distanceOK = false
            isCalibratedForPushup = false
            overlayLandmarks = []
            showSkeleton = false
        case .liningUp:
            coachingBanner = gate.coachingMessage
            feedbackMessage = ""
            secondaryCoachingText = ""
            shoulderImbalanceMetric = 0
            bodyDetected = true
            landmarksVisible = false
            distanceOK = false
            isCalibratedForPushup = false
            overlayLandmarks = []
            showSkeleton = false
        case .locked:
            bodyDetected = smoothed.isBodyDetected
            landmarksVisible = smoothed.areKeyLandmarksVisible
            distanceOK = smoothed.isDistanceOK
            isCalibratedForPushup = smoothed.isCalibratedForPushup

            let isExercising = currentPhase == .down || currentPhase == .ascending || currentPhase == .ready
            let isArmed = currentPhase == .ready || currentPhase == .down || currentPhase == .ascending
            let feedback = feedbackEngine.evaluate(pose: smoothed, isArmed: isArmed, isExercising: isExercising && repCount > 0)

            if feedback.shouldHideSkeleton {
                showSkeleton = false
                coachingBanner = feedback.message
                feedbackMessage = ""
                secondaryCoachingText = feedback.secondaryCoachingMessage ?? ""
            } else {
                showSkeleton = true
                coachingBanner = gate.coachingMessage
                feedbackMessage = feedback.message
                secondaryCoachingText = feedback.secondaryCoachingMessage ?? ""
            }

            if showSkeleton, let d = smoothed.shoulderVerticalDelta {
                shoulderImbalanceMetric = smoothed.worldLandmarks != nil ? d * 1.35 : d
            } else {
                shoulderImbalanceMetric = 0
            }

            let mapped = mapToOverlay(smoothed.landmarks)
            if !mapped.isEmpty {
                overlayLandmarks = mapped
            }
        }

        let repPose: PoseResult? = (gate.state == .locked) ? gate.poseForRepCounting : nil
        let update = repEngine.update(with: repPose)
        currentPhase = update.phase
        repCount = update.repCount

        if let ny = update.noseY { latestNoseY = ny }
        depthPercent = update.depthPercent ?? repEngine.continuousDepthPercent(pose: smoothed)
        if let msg = update.debugMessage { addDebug(msg) }

        refreshWorkoutSubtitle()
        bumpRepAnimationIfNeeded(newCount: update.repCount)
    }

    private func mapToOverlay(_ landmarks: [Landmark]) -> [OverlayLandmark] {
        let minConf = PushupPoseConstants.overlayMinConfidenceDot
        if let layer = previewLayer {
            return landmarks.compactMap { lm in
                guard lm.confidence >= minConf else { return nil }
                let meta = providerType == .mediaPipe
                    ? VisionOrientation.mediaPipeNormalizedToMetadataNormalized(lm.position)
                    : lm.position
                let pt = layer.layerPoint(fromMetadataNormalizedTopLeft: meta)
                return OverlayLandmark(id: lm.type, point: pt, confidence: lm.confidence)
            }
        }
        let w = max(overlaySize.width, 1)
        let h = max(overlaySize.height, 1)
        return landmarks.compactMap { lm in
            guard lm.confidence >= minConf else { return nil }
            let p = providerType == .mediaPipe
                ? VisionOrientation.mediaPipeNormalizedToMetadataNormalized(lm.position)
                : lm.position
            let pt = CGPoint(x: p.x * w, y: p.y * h)
            return OverlayLandmark(id: lm.type, point: pt, confidence: lm.confidence)
        }
    }

    private func updateFPS() {
        frameCount += 1
        let elapsed = Date.now.timeIntervalSince(fpsTimer)
        if elapsed >= 1.0 {
            fps = Double(frameCount) / elapsed
            frameCount = 0
            fpsTimer = .now
        }
    }

    private func refreshWorkoutSubtitle() {
        switch trackingState {
        case .lost:
            workoutStateSubtitle = "Finding you"
        case .liningUp:
            workoutStateSubtitle = "Hold still — locking on"
        case .locked:
            switch currentPhase {
            case .idle:
                workoutStateSubtitle = isCalibratedForPushup ? "Ready" : "Set up — arms & plank"
            case .ready:
                workoutStateSubtitle = "Lower to begin"
            case .down:
                workoutStateSubtitle = "Down"
            case .ascending:
                workoutStateSubtitle = "Ascending"
            case .paused:
                workoutStateSubtitle = "Paused"
            }
        }
    }

    private func bumpRepAnimationIfNeeded(newCount: Int) {
        if newCount > lastRepCount {
            repAnimToken += 1
        }
        lastRepCount = newCount
    }

    private func addDebug(_ message: String) {
        let timestamp = String(format: "%.1f", Date.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
        debugMessages.append("[F\(processedFrameCount) t\(timestamp)] \(message)")
        if debugMessages.count > 200 {
            debugMessages.removeFirst(debugMessages.count - 200)
        }
    }

    private func updateCameraStartupPhase(_ phase: CameraStartupPhase, log: String? = nil) {
        cameraStartupPhase = phase
        if let log {
            addDebug(log)
        }
    }

    private func beginCaptureStartup(attemptID: UUID) {
        let provider: any PoseProvider
        if providerType == .mediaPipe {
            if mediaPipeProvider == nil {
                mediaPipeProvider = MediaPipePoseProvider()
            }
            provider = mediaPipeProvider!
        } else {
            provider = appleVisionProvider
        }
        addDebug("Selected provider: \(provider.providerType.rawValue)")
        updateCameraStartupPhase(.configuringSession, log: "Configuring capture session")

        // Wire callbacks before capture starts so the first frames aren’t dropped.
        cameraManager.onPoseResult = { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handlePoseSample(result)
            }
        }

        cameraManager.onFrameProcessed = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.startupAttemptID == attemptID, self.cameraStartupPhase == .configuringSession {
                    self.cancelStartupWatchdog()
                    self.updateCameraStartupPhase(.running, log: "First frame processed — camera running")
                }
                self.processedFrameCount += 1
                self.updateFPS()
            }
        }
        cameraManager.onStartupEvent = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.addDebug(message)
            }
        }
        startStartupWatchdog(for: attemptID)

        cameraManager.configureAndStart(provider: provider) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.startupAttemptID == attemptID else { return }
                if let error {
                    self.cancelStartupWatchdog()
                    self.updateCameraStartupPhase(.failed, log: "Camera setup failed: \(error.localizedDescription)")
                    self.cameraManager.clearOutputCallbacks()
                    self.cameraErrorMessage = error.localizedDescription
                } else {
                    self.addDebug("Capture session configured — waiting for first frame")
                }
            }
        }
    }

    private func startStartupWatchdog(for attemptID: UUID) {
        cancelStartupWatchdog()
        startupWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            await MainActor.run {
                guard let self else { return }
                guard self.startupAttemptID == attemptID, self.cameraStartupPhase == .configuringSession else { return }
                self.cameraManager.clearOutputCallbacks()
                self.cameraErrorMessage = "The camera did not start in time. This usually means the capture session stalled during startup."
                self.updateCameraStartupPhase(.failed, log: "Camera startup timed out after 8 seconds")
            }
        }
    }

    private func cancelStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
    }

    nonisolated private static func describeAuthorizationStatus(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    nonisolated private static func resolveCameraPermissionBlocking(timeoutSeconds: Double) -> CameraPermissionOutcome {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return .alreadyAuthorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            requestCameraAccessIfNeeded()
            return pollCameraPermissionBlocking(timeoutSeconds: timeoutSeconds)
        @unknown default:
            requestCameraAccessIfNeeded()
            return pollCameraPermissionBlocking(timeoutSeconds: timeoutSeconds)
        }
    }

    nonisolated private static func requestCameraAccessIfNeeded() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            // Intentionally ignored. On some device/OS combinations the completion path appears unreliable,
            // so startup polls authorization status directly instead of trusting this callback to resume.
        }
    }

    nonisolated private static func pollCameraPermissionBlocking(timeoutSeconds: Double) -> CameraPermissionOutcome {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                return .grantedAfterPrompt
            case .denied, .restricted:
                return .denied
            case .notDetermined:
                break
            @unknown default:
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return .timedOut
    }
}

struct Phase0TestView: View {
    @StateObject private var viewModel = Phase0ViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showFaceOrientationTest = false
    @State private var repCountScale: CGFloat = 1.0
    @State private var sessionSaved = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isRunning {
                cameraView
            } else if viewModel.completedSession != nil {
                summaryView
            } else {
                startView
            }
        }
        .fullScreenCover(isPresented: $showFaceOrientationTest) {
            FaceOrientationTestView()
        }
        .overlay(alignment: .top) {
            startupBanner
                .padding(.top, 8)
                .padding(.horizontal, 12)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(viewModel.isRunning)
        .workoutLandscapeWhenActive(viewModel.isRunning)
        .onChange(of: viewModel.completedSession) { _, session in
            guard let session, !sessionSaved else { return }
            SessionStore.save(session: session, context: modelContext)
            sessionSaved = true
        }
        .alert("Can’t start camera", isPresented: Binding(
            get: { viewModel.cameraErrorMessage != nil },
            set: { if !$0 { viewModel.cameraErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.cameraErrorMessage = nil }
        } message: {
            Text(viewModel.cameraErrorMessage ?? "")
        }
    }

    // MARK: - Start

    private var startView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 60)

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))

                Text("PushupCoach — Phase 0 Test")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text("This test validates camera capture, pose detection, rep counting, and form scoring.")
                    .font(.body)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Lean phone against a wall, screen facing you", systemImage: "iphone")
                    Label("Portrait orientation (tall, not sideways)", systemImage: "arrow.up")
                    Label("Step back 2–3 feet and get into pushup position", systemImage: "figure.strengthtraining.traditional")
                    Label("Good lighting, upper body in view", systemImage: "light.max")
                }
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))

                Button {
                    showFaceOrientationTest = true
                } label: {
                    Text("Face orientation test (MediaPipe)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 40)

                Button {
                    viewModel.startCamera()
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isStartingCamera {
                            ProgressView()
                                .tint(.black)
                        }
                        Text(viewModel.isStartingCamera ? viewModel.startupStatusText : "Start Camera")
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 1.0, green: 0.42, blue: 0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                }
                .disabled(viewModel.isStartingCamera)
                .padding(.horizontal, 40)

                startScreenDebugPanel
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Camera + Tracking

    private var cameraView: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreviewView(session: viewModel.captureSession, showSafeFrameGuide: true, onPreviewLayerReady: { layer in
                    viewModel.setPreviewLayer(layer, overlaySize: geo.size)
                })

                if viewModel.cameraStartupPhase == .configuringSession {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text(viewModel.startupStatusText)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                LandmarkOverlayView(
                    landmarks: viewModel.overlayLandmarks,
                    phase: viewModel.currentPhase,
                    showSkeleton: viewModel.showSkeleton
                )

                VStack {
                    Spacer()
                    cameraDebugOverlay
                        .padding(.horizontal, 12)
                        .padding(.bottom, 84)
                }

                VStack {
                    HStack(alignment: .top) {
                        ShoulderLevelHUDView(
                            imbalanceMetric: viewModel.shoulderImbalanceMetric,
                            isVisible: viewModel.trackingState == .locked && viewModel.showSkeleton
                        )
                        .padding(.leading, 12)
                        .padding(.top, 100)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)

                HStack(spacing: 0) {
                    Spacer()
                    DepthBarView(
                        depthPercent: viewModel.depthPercent,
                        targetDepthPercent: 0.7,
                        isActive: viewModel.trackingState == .locked && viewModel.currentPhase != .idle
                    )
                    .frame(height: geo.size.height * 0.4)
                    .padding(.trailing, 12)
                }

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    Spacer(minLength: 0)

                    coachingStrip

                    repCounter

                    Spacer(minLength: 0)

                    bottomBar
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
            .onAppear { viewModel.updateOverlayContainerSize(geo.size) }
            .onChange(of: geo.size) { _, new in viewModel.updateOverlayContainerSize(new) }
        }
        .ignoresSafeArea()
    }

    private var coachingStrip: some View {
        Group {
            let text = primaryCoachingText
            let sub = viewModel.secondaryCoachingText
            if !text.isEmpty || !sub.isEmpty {
                VStack(spacing: 4) {
                    if !text.isEmpty {
                        Text(text)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                    }
                    if !sub.isEmpty, sub != text {
                        Text(sub)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.55))
            }
        }
    }

    private var startupBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(startupBannerColor)
                .frame(width: 10, height: 10)
            Text(viewModel.startupBannerText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(startupBannerColor.opacity(0.9), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var startupBannerColor: Color {
        switch viewModel.cameraStartupPhase {
        case .idle:
            return .gray
        case .requestingPermission:
            return .yellow
        case .configuringSession:
            return Color(red: 1.0, green: 0.42, blue: 0.42)
        case .running:
            return .green
        case .failed:
            return .red
        }
    }

    private var startScreenDebugPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Debug Log")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button("Copy Logs") {
                    viewModel.copyDebugLogsToPasteboard()
                }
                .buttonStyle(Phase0ButtonStyle())
            }

            Text("Tap Copy Logs, then paste the full output into chat.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))

            ScrollView {
                Text(viewModel.debugLogText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180, maxHeight: 240)
            .padding(10)
            .background(.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var cameraDebugOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Runtime Debug")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button("Copy Logs") {
                    viewModel.copyDebugLogsToPasteboard()
                }
                .buttonStyle(Phase0ButtonStyle())
            }

            Text("Phase: \(viewModel.startupBannerText) | Frames: \(viewModel.processedFrameCount) | FPS: \(String(format: "%.1f", viewModel.fps))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))

            ScrollView {
                Text(viewModel.debugLogText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
            .padding(8)
            .background(.black.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(.black.opacity(0.74))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var primaryCoachingText: String {
        if !viewModel.coachingBanner.isEmpty {
            return viewModel.coachingBanner
        }
        if !viewModel.feedbackMessage.isEmpty {
            return viewModel.feedbackMessage
        }
        if viewModel.trackingState == .locked, viewModel.currentPhase == .idle, !viewModel.isCalibratedForPushup {
            return "Face in frame — get arms visible and move into plank."
        }
        return ""
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    statusDot(viewModel.bodyDetected)
                    Text("Body")
                }
                HStack(spacing: 6) {
                    statusDot(viewModel.landmarksVisible)
                    Text("Landmarks")
                }
                HStack(spacing: 6) {
                    statusDot(viewModel.distanceOK)
                    Text("Distance")
                }
            }
            .font(.caption.bold())
            .foregroundStyle(.white)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(String(format: "%.1f", viewModel.fps)) FPS")
                    .font(.caption.monospacedDigit())
                Text(viewModel.providerType.rawValue)
                    .font(.caption2)
                Text("Track: \(String(describing: viewModel.trackingState))")
                    .font(.caption2)
                Text("Phase: \(viewModel.currentPhase.rawValue)")
                    .font(.caption2)
                Text("Depth: \(String(format: "%.0f%%", viewModel.depthPercent * 100))")
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(10)
        .background(.ultraThinMaterial.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var repCounter: some View {
        VStack(spacing: 6) {
            Text("\(viewModel.repCount)")
                .font(.system(size: 88, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                .scaleEffect(repCountScale)
                .onChange(of: viewModel.repAnimToken) { _, _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                        repCountScale = 1.12
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                            repCountScale = 1.0
                        }
                    }
                }

            Text(viewModel.workoutStateSubtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            if viewModel.trackingState == .locked {
                if viewModel.currentPhase == .down {
                    Text("Go lower")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                } else if viewModel.currentPhase == .paused {
                    Text("Get back in frame!")
                        .font(.title3.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if !viewModel.debugMessages.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(viewModel.debugMessages.suffix(5).enumerated()), id: \.offset) { _, msg in
                            Text(msg)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.green.opacity(0.85))
                        }
                    }
                }
                .frame(maxHeight: 56)
                .padding(6)
                .background(.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 12) {
                Button("Switch Provider") {
                    viewModel.switchProvider()
                }
                .buttonStyle(Phase0ButtonStyle())

                Button("Reset") {
                    viewModel.resetSession()
                }
                .buttonStyle(Phase0ButtonStyle())

                Button("Stop") {
                    viewModel.stopCamera()
                }
                .buttonStyle(Phase0ButtonStyle(isPrimary: true))
            }
        }
    }

    // MARK: - Summary

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Workout Complete")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text("\(viewModel.repCount) reps")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))

                if let scores = viewModel.formScores {
                    VStack(spacing: 12) {
                        scoreRow("Composite", scores.composite)
                        scoreRow("Depth", scores.depth)
                        scoreRow("Alignment", scores.alignment)
                        scoreRow("Consistency", scores.consistency)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    if !scores.improvements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggestions")
                                .font(.headline)
                                .foregroundStyle(.white)

                            ForEach(Array(scores.improvements.enumerated()), id: \.offset) { idx, text in
                                HStack(alignment: .top) {
                                    Text("\(idx + 1).")
                                        .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                                    Text(text)
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                                .font(.callout)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Text("Not enough reps for scoring (need 2+)")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                HStack(spacing: 12) {
                    Button("New Session") {
                        sessionSaved = false
                        viewModel.resetSession()
                    }
                    .buttonStyle(Phase0ButtonStyle())

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(Phase0ButtonStyle(isPrimary: true))
                }
                .padding(.bottom, 40)
            }
            .padding()
        }
    }

    private func statusDot(_ ok: Bool) -> some View {
        Circle()
            .fill(ok ? .green : .red)
            .frame(width: 8, height: 8)
    }

    private func scoreRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text("\(value)")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(scoreColor(value))
        }
    }

    private func scoreColor(_ value: Int) -> Color {
        if value >= 80 { return .green }
        if value >= 60 { return .yellow }
        return Color(red: 1.0, green: 0.42, blue: 0.42)
    }
}

struct Phase0ButtonStyle: ButtonStyle {
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.bold())
            .foregroundStyle(isPrimary ? .black : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isPrimary ? Color(red: 1.0, green: 0.42, blue: 0.42) : Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
