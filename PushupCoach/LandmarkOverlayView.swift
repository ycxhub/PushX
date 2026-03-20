import SwiftUI

struct OverlayLandmark: Identifiable {
    let id: LandmarkType
    let point: CGPoint
    let confidence: Float
}

struct LandmarkOverlayView: View {
    let landmarks: [OverlayLandmark]
    let phase: RepCountingEngine.Phase
    let showSkeleton: Bool

    private let connections: [(LandmarkType, LandmarkType)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow),
        (.rightShoulder, .rightElbow),
        (.leftElbow, .leftWrist),
        (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.nose, .leftEye),
        (.nose, .rightEye),
        // MediaPipe additional connections
        (.leftHip, .leftKnee),
        (.rightHip, .rightKnee),
        (.leftKnee, .leftAnkle),
        (.rightKnee, .rightAnkle),
        (.leftAnkle, .leftHeel),
        (.rightAnkle, .rightHeel),
        (.leftHeel, .leftFootIndex),
        (.rightHeel, .rightFootIndex),
        (.leftWrist, .leftPinky),
        (.rightWrist, .rightPinky),
        (.leftWrist, .leftIndex),
        (.rightWrist, .rightIndex),
        (.leftWrist, .leftThumb),
        (.rightWrist, .rightThumb),
    ]

    private var minConfidenceDot: Float { PushupPoseConstants.overlayMinConfidenceDot }
    private var minConfidenceLine: Float { PushupPoseConstants.overlayMinConfidenceLine }

    var body: some View {
        Canvas { context, _ in
            guard showSkeleton else { return }

            let map = Dictionary(uniqueKeysWithValues: landmarks.map { ($0.id, $0) })

            for (from, to) in connections {
                guard let a = map[from], let b = map[to],
                      a.confidence >= minConfidenceLine, b.confidence >= minConfidenceLine else { continue }

                var path = Path()
                path.move(to: a.point)
                path.addLine(to: b.point)
                context.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 2.5)
            }

            for lm in landmarks {
                guard lm.confidence >= minConfidenceDot else { continue }
                let radius: CGFloat = lm.id == .nose ? 8 : 6
                let color = dotColor(for: lm, phase: phase)
                let rect = CGRect(x: lm.point.x - radius, y: lm.point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))

                if lm.confidence > 0.6 {
                    let outer = CGRect(x: lm.point.x - radius - 2, y: lm.point.y - radius - 2, width: (radius + 2) * 2, height: (radius + 2) * 2)
                    context.stroke(Path(ellipseIn: outer), with: .color(color.opacity(0.35)), lineWidth: 1.5)
                }
            }
        }
    }

    private func dotColor(for landmark: OverlayLandmark, phase: RepCountingEngine.Phase) -> Color {
        if landmark.confidence < 0.62 { return .yellow }
        switch phase {
        case .down: return Color(red: 1.0, green: 0.42, blue: 0.42)
        case .ready, .up: return Color(red: 0.3, green: 0.9, blue: 0.5)
        case .idle: return .gray
        case .paused: return .orange
        }
    }
}
