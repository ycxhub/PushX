import SwiftUI
import AVFoundation

@MainActor
final class Phase0ViewModel: ObservableObject {
    @Published var repCount: Int = 0
    @Published var currentPhase: RepCountingEngine.Phase = .idle
    @Published var landmarks: [Landmark] = []
    @Published var fps: Double = 0
    @Published var providerType: PoseProviderType = .appleVision
    @Published var formScores: FormScores?
    @Published var isRunning: Bool = false
    @Published var debugMessages: [String] = []
    @Published var latestNoseY: CGFloat = 0
    @Published var depthPercent: CGFloat = 0

    // Calibration checks displayed to the user.
    @Published var bodyDetected: Bool = false
    @Published var landmarksVisible: Bool = false
    @Published var distanceOK: Bool = false

    let cameraManager = CameraManager()
    private let repEngine = RepCountingEngine()
    private let formEngine = FormScoringEngine()
    private var appleVisionProvider = AppleVisionPoseProvider()

    private var frameCount = 0
    private var fpsTimer: Date = .now

    var captureSession: AVCaptureSession { cameraManager.session }

    func startCamera() {
        cameraManager.configure(provider: appleVisionProvider)

        cameraManager.onPoseResult = { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handlePoseResult(result)
            }
        }

        cameraManager.onFrameProcessed = { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateFPS()
            }
        }

        cameraManager.start()
        isRunning = true
        addDebug("Camera started — provider: \(providerType.rawValue)")
    }

    func stopCamera() {
        cameraManager.stop()
        isRunning = false

        if repEngine.completedReps.count >= 2 {
            formScores = formEngine.computeScores(from: repEngine.completedReps)
        }

        addDebug("Camera stopped. Reps: \(repCount)")
    }

    func resetSession() {
        repEngine.reset()
        repCount = 0
        currentPhase = .idle
        landmarks = []
        formScores = nil
        debugMessages = []
        depthPercent = 0
        latestNoseY = 0
        bodyDetected = false
        landmarksVisible = false
        distanceOK = false
        addDebug("Session reset")
    }

    func switchProvider() {
        providerType = (providerType == .appleVision) ? .mediaPipe : .appleVision

        if providerType == .appleVision {
            cameraManager.switchProvider(appleVisionProvider)
        } else {
            // MediaPipe provider not yet implemented — stay on Apple Vision.
            providerType = .appleVision
            addDebug("MediaPipe not yet available — using Apple Vision")
            return
        }

        addDebug("Switched to \(providerType.rawValue)")
    }

    private func handlePoseResult(_ result: PoseResult) {
        landmarks = result.landmarks

        bodyDetected = result.isBodyDetected
        landmarksVisible = result.areKeyLandmarksVisible
        distanceOK = result.isDistanceOK

        let update = repEngine.update(with: result)
        currentPhase = update.phase
        repCount = update.repCount

        if let ny = update.noseY { latestNoseY = ny }
        if let dp = update.depthPercent { depthPercent = dp }
        if let msg = update.debugMessage { addDebug(msg) }
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
        .preferredColorScheme(.dark)
        .statusBarHidden(viewModel.isRunning)
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
                Label("Place phone on floor, screen facing you", systemImage: "iphone.landscape")
                Label("Keep ~2-3 feet distance", systemImage: "ruler")
                Label("Ensure good lighting", systemImage: "light.max")
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Button {
                viewModel.startCamera()
            } label: {
                Text("Start Camera")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 1.0, green: 0.42, blue: 0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Camera + Tracking

    private var cameraView: some View {
        ZStack {
            CameraPreviewView(session: viewModel.captureSession)
                .ignoresSafeArea()

            LandmarkOverlayView(landmarks: viewModel.landmarks, phase: viewModel.currentPhase)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                repCounter
                Spacer()
                bottomBar
            }
            .padding()
        }
    }

    private var topBar: some View {
        HStack {
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
                Text("Phase: \(viewModel.currentPhase.rawValue)")
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(10)
        .background(.ultraThinMaterial.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var repCounter: some View {
        VStack(spacing: 4) {
            Text("\(viewModel.repCount)")
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))

            if viewModel.currentPhase == .down {
                Text("Go lower")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            } else if viewModel.currentPhase == .paused {
                Text("Get back in frame!")
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
            } else if viewModel.currentPhase == .idle {
                Text("Get into pushup position")
                    .font(.title3.bold())
                    .foregroundStyle(.yellow)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if !viewModel.debugMessages.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.debugMessages.suffix(5), id: \.self) { msg in
                            Text(msg)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.green.opacity(0.8))
                        }
                    }
                }
                .frame(maxHeight: 60)
                .padding(6)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 16) {
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
                    ForEach(viewModel.debugMessages, id: \.self) { msg in
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

    // MARK: - Helpers

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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isPrimary ? Color(red: 1.0, green: 0.42, blue: 0.42) : Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
