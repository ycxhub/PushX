import SwiftUI

struct LandmarkOverlayView: View {
    let landmarks: [Landmark]
    let phase: RepCountingEngine.Phase

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
    ]

    var body: some View {
        Canvas { context, size in
            let landmarkMap = Dictionary(uniqueKeysWithValues: landmarks.map { ($0.type, $0) })

            for (from, to) in connections {
                guard let a = landmarkMap[from], let b = landmarkMap[to],
                      a.confidence > 0.3, b.confidence > 0.3 else { continue }

                let pointA = CGPoint(x: a.position.x * size.width, y: a.position.y * size.height)
                let pointB = CGPoint(x: b.position.x * size.width, y: b.position.y * size.height)

                var path = Path()
                path.move(to: pointA)
                path.addLine(to: pointB)
                context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 2)
            }

            for landmark in landmarks {
                guard landmark.confidence > 0.3 else { continue }
                let point = CGPoint(x: landmark.position.x * size.width, y: landmark.position.y * size.height)
                let radius: CGFloat = landmark.type == .nose ? 8 : 6
                let color = dotColor(for: landmark, phase: phase)

                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))

                if landmark.confidence > 0.7 {
                    let outerRect = CGRect(x: point.x - radius - 2, y: point.y - radius - 2, width: (radius + 2) * 2, height: (radius + 2) * 2)
                    context.stroke(Path(ellipseIn: outerRect), with: .color(color.opacity(0.4)), lineWidth: 1.5)
                }
            }
        }
    }

    private func dotColor(for landmark: Landmark, phase: RepCountingEngine.Phase) -> Color {
        if landmark.confidence < 0.5 { return .yellow }
        switch phase {
        case .down: return Color(red: 1.0, green: 0.42, blue: 0.42)
        case .ready, .up: return Color(red: 0.3, green: 0.9, blue: 0.5)
        case .idle: return .gray
        case .paused: return .orange
        }
    }
}
