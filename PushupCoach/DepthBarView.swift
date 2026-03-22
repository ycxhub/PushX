import SwiftUI

/// Vertical bar showing real-time push-up depth as a 0–1 fill percentage.
/// Electric blue at top (up position), secondary cyan at full depth, with a target line.
struct DepthBarView: View {
    let depthPercent: CGFloat
    let targetDepthPercent: CGFloat
    let isActive: Bool

    init(depthPercent: CGFloat, targetDepthPercent: CGFloat = 0.7, isActive: Bool = true) {
        self.depthPercent = depthPercent
        self.targetDepthPercent = targetDepthPercent
        self.isActive = isActive
    }

    private let barWidth: CGFloat = 14
    private let cornerRadius: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.nkSurfaceContainerHighest)
                    .frame(width: barWidth)

                if isActive {
                    let fillH = max(0, min(h, h * depthPercent))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.nkPrimary, Color.nkPrimaryContainer],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: fillH)
                        .animation(.easeOut(duration: 0.08), value: depthPercent)
                }

                let targetY = h * (1 - targetDepthPercent)
                Rectangle()
                    .fill(Color.nkOnSurface.opacity(0.6))
                    .frame(width: barWidth + 6, height: 2)
                    .position(x: geo.size.width / 2, y: targetY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: barWidth + 8)
        .opacity(isActive ? 1.0 : 0.3)
        .accessibilityValue("\(Int(depthPercent * 100)) percent depth")
    }
}
