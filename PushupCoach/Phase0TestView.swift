import SwiftUI
import AVFoundation
import UIKit

@MainActor
final class Phase0ViewModel: ObservableObject {
    @Published var repCount: Int = 0
    @Published var currentPhase: RepCountingEngine.Phase = .idle
    @Published var overlayLandmarks: [OverlayLandmark] = []
    @Published var showSkeleton: Bool = false
    @Published var trackingState: PoseTrackingState = .lost
    @Published var coachingBanner: String = ""
    @Published var fps: Double = 0
    @Published var providerType: PoseProviderType = .mediaPipe
    @Published var formScores: FormScores?
    @Published var isRunning: Bool = false
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
    @Published var isStartingCamera: Bool = false

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

    var captureSession: AVCaptureSession { cameraManager.session }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer, overlaySize: CGSize) {
        previewLayer = layer
        self.overlaySize = overlaySize
        objectWillChange.send()
    }

    func updateOverlayContainerSize(_ size: CGSize) {
        overlaySize = size
    }

    func startCamera() {
        Task { @MainActor in
            cameraErrorMessage = nil

            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                authorized = true
            case .denied, .restricted:
                cameraErrorMessage = "Camera access is off for PushupCoach. Enable it in Settings → Privacy & Security → Camera."
                addDebug("Camera access denied — enable in Settings › Privacy & Camera")
                return
            case .notDetermined:
                authorized = await AVCaptureDevice.requestAccess(for: .video)
            @unknown default:
                authorized = await AVCaptureDevice.requestAccess(for: .video)
            }

            guard authorized else {
                cameraErrorMessage = "Camera access is required to start a session. You can enable it in Settings → Privacy & Security → Camera."
                addDebug("Camera access denied after prompt")
                return
            }

            isStartingCamera = true
            defer { isStartingCamera = false }

            // MediaPipe (Metal) must initialize on the main thread; `Task.detached` here deadlocks
            // the main actor waiting on work that needs the main queue.
            let provider: any PoseProvider
            if providerType == .mediaPipe {
                if mediaPipeProvider == nil {
                    mediaPipeProvider = MediaPipePoseProvider()
                }
                provider = mediaPipeProvider!
            } else {
                provider = appleVisionProvider
            }

            let setupError: Error? = await withCheckedContinuation { cont in
                cameraManager.configureAndStart(provider: provider) { error in
                    cont.resume(returning: error)
                }
            }

            if let setupError {
                cameraErrorMessage = setupError.localizedDescription
                addDebug("Camera setup failed: \(setupError.localizedDescription)")
                return
            }

            cameraManager.onPoseResult = { [weak self] result in
                Task { @MainActor [weak self] in
                    self?.handlePoseSample(result)
                }
            }

            cameraManager.onFrameProcessed = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.updateFPS()
                }
            }

            isRunning = true
            addDebug("Camera started — provider: \(providerType.rawValue). Phone flat on floor, portrait, screen up.")
        }
    }

    func stopCamera() {
        cameraManager.clearOutputCallbacks()
        isRunning = false

        cameraManager.stop { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.repEngine.completedReps.count >= 2 {
                    self.formScores = self.formEngine.computeScores(from: self.repEngine.completedReps)
                }
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
        debugMessages = []
        depthPercent = 0
        latestNoseY = 0
        bodyDetected = false
        landmarksVisible = false
        distanceOK = false
        isCalibratedForPushup = false
        latestSmoothedPose = nil
        addDebug("Session reset")
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

            let isExercising = currentPhase == .down || currentPhase == .up || currentPhase == .ready
            let feedback = feedbackEngine.evaluate(pose: smoothed, isExercising: isExercising && repCount > 0)

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
            case .up:
                workoutStateSubtitle = "Up"
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
        debugMessages.append("[\(timestamp)] \(message)")
        if debugMessages.count > 50 {
            debugMessages.removeFirst(debugMessages.count - 50)
        }
    }
}

struct Phase0TestView: View {
    @StateObject private var viewModel = Phase0ViewModel()
    @State private var showFaceOrientationTest = false
    @State private var repCountScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isRunning {
                cameraView
            } else if let scores = viewModel.formScores {
                scoresView(scores)
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
        VStack(spacing: 24) {
            Spacer()

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
                Label("Place phone flat on the floor, screen facing up", systemImage: "iphone")
                Label("Portrait orientation (tall, not sideways)", systemImage: "arrow.up")
                Label("Get into pushup position above the phone", systemImage: "figure.strengthtraining.traditional")
                Label("Good lighting, ~arm's length away", systemImage: "light.max")
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.85))

            Spacer()

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
                    Text(viewModel.isStartingCamera ? "Starting…" : "Start Camera")
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
            .padding(.bottom, 40)
        }
    }

    // MARK: - Camera + Tracking

    private var cameraView: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreviewView(session: viewModel.captureSession, showSafeFrameGuide: true) { layer in
                    viewModel.setPreviewLayer(layer, overlaySize: geo.size)
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

    // MARK: - Scores

    private func scoresView(_ scores: FormScores) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Workout Complete")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text("\(viewModel.repCount) reps")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))

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

                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug Log")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                    ForEach(Array(viewModel.debugMessages.enumerated()), id: \.offset) { _, msg in
                        Text(msg)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                Button("New Session") {
                    viewModel.resetSession()
                }
                .buttonStyle(Phase0ButtonStyle(isPrimary: true))
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
