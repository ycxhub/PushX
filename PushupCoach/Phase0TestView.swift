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
    @Published private(set) var sessionStartTime: Date?

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

        // Wire callbacks before capture starts so the first frames aren't dropped.
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
    @State private var showDebugPanel = false

    var body: some View {
        ZStack {
            Color.nkSurface.ignoresSafeArea()

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
        .preferredColorScheme(.dark)
        .statusBarHidden(viewModel.isRunning)
        .workoutLandscapeWhenActive(viewModel.isRunning)
        .onChange(of: viewModel.completedSession) { _, session in
            guard let session, !sessionSaved else { return }
            SessionStore.save(session: session, context: modelContext)
            sessionSaved = true
        }
        .alert("Camera Unavailable", isPresented: Binding(
            get: { viewModel.cameraErrorMessage != nil },
            set: { if !$0 { viewModel.cameraErrorMessage = nil } }
        )) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                viewModel.cameraErrorMessage = nil
            }
            Button("Try Again") {
                viewModel.cameraErrorMessage = nil
                viewModel.startCamera()
            }
            Button("Cancel", role: .cancel) { viewModel.cameraErrorMessage = nil }
        } message: {
            Text(viewModel.cameraErrorMessage ?? "")
        }
    }

    // MARK: - Start

    private var startView: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("PushX")
                        .font(.system(size: 24, weight: .black))
                        .tracking(3)
                        .foregroundStyle(Color.nkPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.nkOnSurfaceVariant)
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, NKSpacing.xl)
                .padding(.top, NKSpacing.lg)

                VStack(alignment: .leading, spacing: NKSpacing.sm) {
                    Text("STEP 01 / CALIBRATION")
                        .nkPrimaryLabel()
                    Text("Position Your\nStation")
                        .font(.nkHeadlineMD)
                        .tracking(-0.5)
                        .foregroundStyle(Color.nkOnSurface)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NKSpacing.xl)
                .padding(.top, NKSpacing.section)

                VStack(spacing: NKSpacing.md) {
                    checklistItem(icon: "iphone", text: "Phone against wall, screen facing you", checked: true)
                    checklistItem(icon: "arrow.up", text: "Portrait orientation", checked: true)
                    checklistItem(icon: "figure.strengthtraining.traditional", text: "2–3 feet back in pushup position", checked: false)
                    checklistItem(icon: "light.max", text: "Bright lighting, upper body visible", checked: false)
                }
                .padding(.horizontal, NKSpacing.xl)
                .padding(.top, NKSpacing.xxxl)

                HStack(spacing: NKSpacing.lg) {
                    settingIcon(icon: "camera.fill", label: "FRONT CAMERA")
                    settingIcon(icon: "light.max", label: "BRIGHT LIGHTING")
                }
                .padding(.horizontal, NKSpacing.xl)
                .padding(.top, NKSpacing.xxl)

                HStack(alignment: .top, spacing: NKSpacing.lg) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(Color.nkPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.nkPrimary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: NKSpacing.micro) {
                        Text("PRO TIP: CONTRAST")
                            .nkPrimaryLabel()
                        Text("Avoid dark clothes against dark floors. High contrast between your body and background improves tracking accuracy.")
                            .font(.nkBodyMD)
                            .foregroundStyle(Color.nkOnSurfaceVariant)
                            .lineSpacing(3)
                    }
                }
                .padding(NKSpacing.xl)
                .background(Color.nkSurfaceContainerHighest.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.nkPrimary.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, NKSpacing.xl)
                .padding(.top, NKSpacing.xxl)

                VStack(spacing: NKSpacing.md) {
                    Button {
                        viewModel.startCamera()
                    } label: {
                        HStack(spacing: NKSpacing.md) {
                            if viewModel.isStartingCamera {
                                ProgressView()
                                    .tint(Color.nkOnPrimaryContainer)
                            }
                            Text(viewModel.isStartingCamera ? viewModel.startupStatusText : "Begin Calibration")
                        }
                    }
                    .buttonStyle(NKPrimaryButtonStyle())
                    .disabled(viewModel.isStartingCamera)
                    .accessibilityHint("Starts the camera for pushup tracking")

                    Button {
                        showFaceOrientationTest = true
                    } label: {
                        Text("Face Orientation Test")
                    }
                    .buttonStyle(NKSecondaryButtonStyle())

                    Button {
                        showDebugPanel.toggle()
                    } label: {
                        Text(showDebugPanel ? "Hide Debug" : "Show Debug")
                            .font(.nkLabelXS)
                            .foregroundStyle(Color.nkOutline)
                    }
                    .padding(.top, NKSpacing.sm)
                }
                .padding(.horizontal, NKSpacing.xl)
                .padding(.top, NKSpacing.section)

                if showDebugPanel {
                    debugPanel
                        .padding(.horizontal, NKSpacing.xl)
                        .padding(.top, NKSpacing.lg)
                }

                Spacer(minLength: NKSpacing.section)
            }
        }
        .nkPageBackground()
    }

    private func checklistItem(icon: String, text: String, checked: Bool) -> some View {
        HStack(spacing: NKSpacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(checked ? Color.nkPrimary.opacity(0.1) : Color.nkSurfaceContainerHighest)
                    .frame(width: 20, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(checked ? Color.nkPrimary.opacity(0.3) : Color.nkOutlineVariant.opacity(0.3), lineWidth: 1)
                    )
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.nkPrimary)
                }
            }
            Text(text)
                .font(.nkBodyMD)
                .foregroundStyle(Color.nkOnSurface)
            Spacer()
        }
        .padding(NKSpacing.lg)
        .background(Color.nkSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.nkOutlineVariant.opacity(0.05), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(text): \(checked ? "ready" : "pending")")
    }

    private func settingIcon(icon: String, label: String) -> some View {
        VStack(spacing: NKSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.nkPrimary)
            Text(label)
                .font(.nkLabelXS)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.nkOnSurface)
        }
        .frame(maxWidth: .infinity)
        .padding(NKSpacing.xl)
        .nkCardElevated()
    }

    // MARK: - Camera + Tracking

    private var cameraView: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreviewView(session: viewModel.captureSession, showSafeFrameGuide: true, onPreviewLayerReady: { layer in
                    viewModel.setPreviewLayer(layer, overlaySize: geo.size)
                })

                if viewModel.cameraStartupPhase == .configuringSession {
                    VStack(spacing: NKSpacing.md) {
                        ProgressView()
                            .tint(Color.nkPrimary)
                        Text(viewModel.startupStatusText)
                            .font(.nkLabelSM)
                            .textCase(.uppercase)
                            .tracking(1)
                            .foregroundStyle(Color.nkOnSurface)
                    }
                    .padding(.horizontal, NKSpacing.xxl)
                    .padding(.vertical, NKSpacing.xl)
                    .background(Color.nkSurface.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .nkAmbientGlow()
                }

                LandmarkOverlayView(
                    landmarks: viewModel.overlayLandmarks,
                    phase: viewModel.currentPhase,
                    showSkeleton: viewModel.showSkeleton
                )

                VStack {
                    HStack(alignment: .top) {
                        ShoulderLevelHUDView(
                            imbalanceMetric: viewModel.shoulderImbalanceMetric,
                            isVisible: viewModel.trackingState == .locked && viewModel.showSkeleton
                        )
                        .padding(.leading, NKSpacing.md)
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
                    .padding(.trailing, NKSpacing.md)
                }

                VStack(spacing: 0) {
                    cameraTopBar
                        .padding(.horizontal, NKSpacing.md)
                        .padding(.top, NKSpacing.sm)

                    Spacer(minLength: 0)

                    coachingStrip

                    repCounter

                    Spacer(minLength: 0)

                    cameraBottomBar
                        .padding(.horizontal, NKSpacing.md)
                        .padding(.bottom, NKSpacing.md)
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
                VStack(spacing: NKSpacing.micro) {
                    if !text.isEmpty {
                        HStack(spacing: NKSpacing.sm) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.nkPrimary)
                            Text(text)
                                .font(.system(size: 14, weight: .black))
                                .textCase(.uppercase)
                                .tracking(1)
                                .foregroundStyle(Color.nkOnSurface)
                        }
                    }
                    if !sub.isEmpty, sub != text {
                        Text(sub)
                            .font(.nkLabelSM)
                            .foregroundStyle(Color.nkOnSurfaceVariant)
                    }
                }
                .padding(.horizontal, NKSpacing.xl)
                .padding(.vertical, NKSpacing.md)
                .frame(maxWidth: .infinity)
                .background(Color.nkPrimary.opacity(0.1))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.nkPrimary)
                        .frame(width: 4)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Coaching: \(text). \(sub)")
            }
        }
    }

    private var primaryCoachingText: String {
        if !viewModel.coachingBanner.isEmpty {
            return viewModel.coachingBanner
        }
        if !viewModel.feedbackMessage.isEmpty {
            return viewModel.feedbackMessage
        }
        if viewModel.trackingState == .locked, viewModel.currentPhase == .idle, !viewModel.isCalibratedForPushup {
            return "Get arms visible — move into plank"
        }
        return ""
    }

    private var cameraTopBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: NKSpacing.xs) {
                trackingIndicator("BODY", ok: viewModel.bodyDetected)
                trackingIndicator("LANDMARKS", ok: viewModel.landmarksVisible)
                trackingIndicator("DISTANCE", ok: viewModel.distanceOK)
            }
            .padding(NKSpacing.md)
            .background(Color.nkSurface.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            VStack(alignment: .trailing, spacing: NKSpacing.micro) {
                Text("ELAPSED")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.nkOutline)
                if let start = viewModel.sessionStartTime {
                    Text(start, style: .timer)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.nkPrimary)
                }
            }
            .padding(.horizontal, NKSpacing.md)
            .padding(.vertical, NKSpacing.sm)
            .background(Color.nkSurfaceContainerHighest.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func trackingIndicator(_ label: String, ok: Bool) -> some View {
        HStack(spacing: NKSpacing.xs) {
            Circle()
                .fill(ok ? Color.nkPrimary : Color.nkError)
                .frame(width: 6, height: 6)
                .shadow(color: ok ? Color.nkPrimary.opacity(0.6) : Color.nkError.opacity(0.6), radius: 4)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.nkOnSurface)
        }
    }

    private var repCounter: some View {
        VStack(spacing: NKSpacing.sm) {
            Text("\(viewModel.repCount)")
                .font(.system(size: 96, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color.nkOnSurface)
                .shadow(color: Color.nkPrimary.opacity(0.3), radius: 24)
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
                .accessibilityLabel("\(viewModel.repCount) reps")

            Text(viewModel.workoutStateSubtitle.uppercased())
                .font(.nkLabelSM)
                .tracking(1.5)
                .foregroundStyle(Color.nkOnSurfaceVariant)

            if viewModel.trackingState == .locked {
                if viewModel.currentPhase == .down {
                    Text("GO LOWER")
                        .font(.system(size: 16, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Color.nkPrimary)
                } else if viewModel.currentPhase == .paused {
                    Text("GET BACK IN FRAME")
                        .font(.system(size: 16, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Color.nkError)
                }
            }
        }
    }

    private var cameraBottomBar: some View {
        VStack(spacing: NKSpacing.md) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.nkSurfaceContainer)
                    Rectangle()
                        .fill(Color.nkPrimary)
                        .frame(width: geo.size.width * min(1, CGFloat(viewModel.repCount) / 20.0))
                }
            }
            .frame(height: 3)
            .clipShape(RoundedRectangle(cornerRadius: 2))

            HStack(spacing: NKSpacing.lg) {
                Button {
                    viewModel.stopCamera()
                } label: {
                    HStack(spacing: NKSpacing.sm) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 16))
                        Text("End Set")
                    }
                }
                .buttonStyle(NKPrimaryButtonStyle())
                .accessibilityHint("Ends the current set and shows your scores")

                Button {
                    viewModel.switchProvider()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.nkOnSurface)
                        .frame(width: 52, height: 52)
                        .background(Color.nkSurfaceContainerHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.nkOutlineVariant.opacity(0.15), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Switch pose provider")
            }
        }
    }

    // MARK: - Summary

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: NKSpacing.sm) {
                    Text("SESSION COMPLETED")
                        .nkPrimaryLabel()
                    Text("Pushup\nPerformance")
                        .font(.nkHeadlineMD)
                        .tracking(-0.5)
                        .foregroundStyle(Color.nkOnSurface)
                    if let session = viewModel.completedSession {
                        Text(session.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .font(.nkBodyMD)
                            .foregroundStyle(Color.nkOnSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NKSpacing.xl)
                .padding(.top, NKSpacing.xxl)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: NKSpacing.micro) {
                        Text("REPS")
                            .nkTechnicalLabel()
                        Text("\(viewModel.repCount)")
                            .font(.nkDisplayLG)
                            .monospacedDigit()
                            .foregroundStyle(Color.nkOnSurface)
                    }
                    Spacer()
                    if let scores = viewModel.formScores {
                        VStack(alignment: .trailing, spacing: NKSpacing.micro) {
                            Text("\(scores.composite)")
                                .font(.nkDisplayLG)
                                .monospacedDigit()
                                .foregroundStyle(Color.nkPrimary)
                                .shadow(color: Color.nkPrimary.opacity(0.3), radius: 16)
                            Text("FORM SCORE")
                                .nkTechnicalLabel()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Form score: \(scores.composite) out of 100, \(Color.nkScoreLabel(scores.composite))")
                    }
                }
                .padding(.horizontal, NKSpacing.xl)
                .padding(.top, NKSpacing.xxxl)

                if let scores = viewModel.formScores {
                    summaryScoresGrid(scores)
                        .padding(.horizontal, NKSpacing.xl)
                        .padding(.top, NKSpacing.xxl)

                    if !scores.improvements.isEmpty {
                        summaryImprovements(scores.improvements)
                            .padding(.horizontal, NKSpacing.xl)
                            .padding(.top, NKSpacing.xxl)
                    }
                } else {
                    VStack(spacing: NKSpacing.md) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.nkOutlineVariant)
                        Text("Complete 2+ reps for form scoring")
                            .font(.nkBodyMD)
                            .foregroundStyle(Color.nkOnSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(NKSpacing.section)
                    .nkCard()
                    .padding(.horizontal, NKSpacing.xl)
                    .padding(.top, NKSpacing.xxl)
                }

                VStack(spacing: NKSpacing.md) {
                    Button {
                        sessionSaved = false
                        viewModel.resetSession()
                    } label: {
                        HStack(spacing: NKSpacing.sm) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("New Session")
                        }
                    }
                    .buttonStyle(NKPrimaryButtonStyle())

                    Button { dismiss() } label: {
                        Text("Done")
                    }
                    .buttonStyle(NKSecondaryButtonStyle())
                }
                .padding(.horizontal, NKSpacing.xl)
                .padding(.top, NKSpacing.section)
                .padding(.bottom, NKSpacing.section)
            }
        }
        .nkPageBackground()
    }

    private func summaryScoresGrid(_ scores: FormScores) -> some View {
        VStack(spacing: NKSpacing.lg) {
            HStack(spacing: NKSpacing.lg) {
                summaryMetricCard("DEPTH", scores.depth)
                summaryMetricCard("ALIGNMENT", scores.alignment)
            }
            HStack(spacing: NKSpacing.lg) {
                summaryMetricCard("CONSISTENCY", scores.consistency)
                summaryMetricCard("COMPOSITE", scores.composite)
            }
        }
    }

    private func summaryMetricCard(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: NKSpacing.sm) {
            Text(label)
                .font(.nkLabelXS)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.nkOnSurfaceVariant)
            HStack(alignment: .firstTextBaseline, spacing: NKSpacing.micro) {
                Text("\(value)")
                    .font(.system(size: 28, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.nkScoreColor(value))
                Text(Color.nkScoreLabel(value))
                    .font(.nkLabelXS)
                    .foregroundStyle(Color.nkOnSurfaceVariant)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.nkSurfaceContainerHighest)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.nkScoreColor(value), Color.nkScoreColor(value).opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(value) / 100.0)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NKSpacing.xl)
        .nkCardElevated()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) out of 100, \(Color.nkScoreLabel(value))")
    }

    private func summaryImprovements(_ improvements: [String]) -> some View {
        VStack(alignment: .leading, spacing: NKSpacing.lg) {
            Text("FORM CALIBRATION TIPS")
                .nkPrimaryLabel()

            ForEach(Array(improvements.enumerated()), id: \.offset) { idx, text in
                HStack(alignment: .top, spacing: NKSpacing.lg) {
                    Text(String(format: "%02d", idx + 1))
                        .font(.system(size: 20, weight: .heavy))
                        .italic()
                        .foregroundStyle(Color.nkOutlineVariant)
                    Text(text)
                        .font(.nkBodyMD)
                        .foregroundStyle(Color.nkOnSurfaceVariant)
                        .lineSpacing(3)
                }
                .padding(NKSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.nkSurfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Debug Panel (hidden by default)

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: NKSpacing.md) {
            HStack {
                Text("DEBUG LOG")
                    .nkTechnicalLabel()
                Spacer()
                Button {
                    viewModel.copyDebugLogsToPasteboard()
                } label: {
                    Text("Copy")
                }
                .buttonStyle(NKGhostButtonStyle())
            }

            ScrollView {
                Text(viewModel.debugLogText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.nkPrimary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 140, maxHeight: 200)
            .padding(NKSpacing.md)
            .background(Color.nkSurfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(NKSpacing.lg)
        .nkCardElevated()
    }
}

