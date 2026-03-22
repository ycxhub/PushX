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
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", session.startedAt),
                    y: .value("Score", session.compositeScore ?? 0)
                )
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.42))
                .symbolSize(30)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(.white.opacity(0.15))
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(height: 180)
            .padding(.horizontal, 4)
        } else {
            Text("Complete 2+ scored sets to see your trend")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.5))
                .frame(height: 80)
                .frame(maxWidth: .infinity)
        }
    }
}
