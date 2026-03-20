import SwiftUI
import AVFoundation
import UIKit

@MainActor
final class FaceOrientationViewModel: ObservableObject {
    @Published var screenPoints: [CGPoint] = []
    @Published var fps: Double = 0

    let faceCamera = FaceDebugCameraManager()

    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var overlaySize: CGSize = UIScreen.main.bounds.size
    private var frameCount = 0
    private var fpsTimer = Date.now

    var captureSession: AVCaptureSession { faceCamera.session }

    init() {
        faceCamera.onLandmarks = { [weak self] normalized in
            Task { @MainActor [weak self] in
                self?.applyLandmarks(normalized)
                self?.tickFPS()
            }
        }
    }

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer, size: CGSize) {
        previewLayer = layer
        overlaySize = size
    }

    func updateOverlaySize(_ size: CGSize) {
        overlaySize = size
    }

    func start() {
        faceCamera.configure()
        faceCamera.start()
    }

    func stop() {
        faceCamera.stop()
        screenPoints = []
    }

    private func applyLandmarks(_ normalized: [CGPoint]) {
        let metadataPoints = normalized.map(VisionOrientation.mediaPipeNormalizedToMetadataNormalized)

        if let layer = previewLayer {
            screenPoints = metadataPoints.map { layer.layerPoint(fromMetadataNormalizedTopLeft: $0) }
        } else {
            let w = max(overlaySize.width, 1)
            let h = max(overlaySize.height, 1)
            screenPoints = metadataPoints.map { CGPoint(x: $0.x * w, y: $0.y * h) }
        }
    }

    private func tickFPS() {
        frameCount += 1
        let elapsed = Date.now.timeIntervalSince(fpsTimer)
        if elapsed >= 1.0 {
            fps = Double(frameCount) / elapsed
            frameCount = 0
            fpsTimer = .now
        }
    }
}

/// MediaPipe Face Landmarker overlay to verify portrait orientation and mirroring while seated.
struct FaceOrientationTestView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FaceOrientationViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    CameraPreviewView(session: viewModel.captureSession) { layer in
                        viewModel.setPreviewLayer(layer, size: geo.size)
                    }

                    FaceLandmarkCanvasView(points: viewModel.screenPoints)
                        .allowsHitTesting(false)
                }
                .onChange(of: geo.size) { _, new in
                    viewModel.updateOverlaySize(new)
                }
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                    .padding(12)

                    Spacer()

                    Text(String(format: "%.1f FPS", viewModel.fps))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(12)
                }

                Spacer()

                VStack(spacing: 8) {
                    Text("Face orientation test")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Move head left/right and up/down — dots should follow the same way on screen.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.55))
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            }
            viewModel.start()
        }
        .onDisappear { viewModel.stop() }
    }
}

/// Draws dense face landmarks as a lightweight “mesh” of dots (and a few key polylines).
private struct FaceLandmarkCanvasView: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, _ in
            guard !points.isEmpty else { return }

            for p in points {
                let r: CGFloat = 1.2
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.green.opacity(0.85)))
            }

            if points.count > 10 {
                strokePolyline(context: context, indices: FaceMeshTopology.faceOval, color: .white.opacity(0.35), closePath: true)
                strokePolyline(context: context, indices: FaceMeshTopology.lipsOuter, color: Color(red: 1, green: 0.42, blue: 0.42).opacity(0.5), closePath: false)
            }
        }
    }

    private func strokePolyline(context: GraphicsContext, indices: [Int], color: Color, closePath: Bool) {
        var path = Path()
        var started = false
        for i in indices {
            guard i < points.count else { continue }
            let p = points[i]
            if !started {
                path.move(to: p)
                started = true
            } else {
                path.addLine(to: p)
            }
        }
        if closePath { path.closeSubpath() }
        context.stroke(path, with: .color(color), lineWidth: 1.0)
    }
}

/// Subset of MediaPipe Face Mesh topology for readable overlay (indices into 478 landmarks).
private enum FaceMeshTopology {
    /// Approximate face oval — closed loop.
    static let faceOval: [Int] = [
        10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
        397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
        172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109
    ]

    static let lipsOuter: [Int] = [
        61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291, 375, 321, 405, 314, 17, 84, 181, 91, 146
    ]
}
