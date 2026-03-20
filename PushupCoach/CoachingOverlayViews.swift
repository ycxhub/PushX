import SwiftUI

// MARK: - Shoulder level (live alignment)

/// Maps shoulder vertical imbalance to a 0…1 bar (0 = level).
struct ShoulderLevelHUDView: View {
    /// 0 = perfectly level; larger = more tilt (clamped for display).
    let imbalanceMetric: CGFloat
    let isVisible: Bool

    /// Normalized tilt severity 0…1 for the bar fill.
    private var tiltSeverity: CGFloat {
        min(max(imbalanceMetric / 0.08, 0), 1)
    }

    var body: some View {
        Group {
            if isVisible {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shoulders")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.85))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                            Capsule()
                                .fill(levelColor)
                                .frame(width: max(4, geo.size.width * tiltSeverity))
                        }
                    }
                    .frame(width: 72, height: 8)
                    Text(levelLabel)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(10)
                .background(.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var levelColor: Color {
        if tiltSeverity < 0.25 { return Color(red: 0.3, green: 0.9, blue: 0.5) }
        if tiltSeverity < 0.55 { return .yellow }
        return Color(red: 1.0, green: 0.42, blue: 0.42)
    }

    private var levelLabel: String {
        if tiltSeverity < 0.25 { return "Level" }
        if tiltSeverity < 0.55 { return "Minor tilt" }
        return "Even out shoulders"
    }
}
