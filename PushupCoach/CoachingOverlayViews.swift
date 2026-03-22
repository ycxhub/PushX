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
                VStack(alignment: .leading, spacing: NKSpacing.micro) {
                    Text("SHOULDERS")
                        .font(.nkLabelXS)
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color.nkOnSurfaceVariant)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.nkSurfaceContainerHighest)
                            Capsule()
                                .fill(levelColor)
                                .frame(width: max(4, geo.size.width * tiltSeverity))
                        }
                    }
                    .frame(width: 72, height: 8)

                    Text(levelLabel)
                        .font(.nkLabelSM)
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(Color.nkOnSurface)
                }
                .padding(NKSpacing.md)
                .background(Color.nkSurface.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var levelColor: Color {
        if tiltSeverity < 0.25 { return Color.nkPrimary }
        if tiltSeverity < 0.55 { return Color.nkSecondary }
        return Color.nkError
    }

    private var levelLabel: String {
        if tiltSeverity < 0.25 { return "Level" }
        if tiltSeverity < 0.55 { return "Minor tilt" }
        return "Even out shoulders"
    }
}
