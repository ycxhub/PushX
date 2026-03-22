import SwiftUI
import Charts

struct FormTrendChart: View {
    let sessions: [PushupSession]

    private var scoredSessions: [PushupSession] {
        sessions
            .filter { $0.compositeScore != nil }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        if scoredSessions.count >= 2 {
            Chart(scoredSessions, id: \.id) { session in
                LineMark(
                    x: .value("Date", session.startedAt),
                    y: .value("Score", session.compositeScore ?? 0)
                )
                .foregroundStyle(Color.nkPrimary)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", session.startedAt),
                    y: .value("Score", session.compositeScore ?? 0)
                )
                .foregroundStyle(Color.nkPrimary)
                .symbolSize(30)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.nkOutlineVariant.opacity(0.15))
                    AxisValueLabel()
                        .foregroundStyle(Color.nkOnSurfaceVariant)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Color.nkOnSurfaceVariant)
                }
            }
            .frame(height: 180)
            .padding(.horizontal, NKSpacing.micro)
        } else {
            Text("Complete 2+ scored sets to see your trend")
                .font(.nkBodyMD)
                .foregroundStyle(Color.nkOnSurfaceVariant)
                .frame(height: 80)
                .frame(maxWidth: .infinity)
        }
    }
}
