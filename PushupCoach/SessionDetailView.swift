import SwiftUI

struct SessionDetailView: View {
    let session: PushupSession
    @State private var copiedToast = false

    private let coral = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                if session.hasScores {
                    scoresSection
                } else {
                    noScoresSection
                }
                if !session.improvements.isEmpty {
                    improvementsSection
                }
                if !session.reps.isEmpty {
                    repsSection
                }
                exportButton
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Session Detail")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if copiedToast {
                Text("Copied to clipboard")
                    .font(.callout.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(coral)
                    .clipShape(Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: copiedToast)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            Text("\(session.repCount)")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundStyle(coral)

            Text(session.repCount == 1 ? "rep" : "reps")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 16) {
                metricPill("Duration", formatDuration(session.durationSeconds))
                metricPill("Provider", session.providerType)
                if let avg = session.averageRepDuration {
                    metricPill("Avg/rep", String(format: "%.1fs", avg))
                }
            }
        }
    }

    private var scoresSection: some View {
        VStack(spacing: 12) {
            scoreRow("Composite", session.compositeScore)
            scoreRow("Depth", session.depthScore)
            scoreRow("Alignment", session.alignmentScore)
            scoreRow("Consistency", session.consistencyScore)
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var noScoresSection: some View {
        Text("Not enough reps for scoring (need 2+)")
            .font(.callout)
            .foregroundStyle(.white.opacity(0.5))
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var improvementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions")
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(Array(session.improvements.enumerated()), id: \.offset) { idx, text in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(idx + 1).")
                        .foregroundStyle(coral)
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

    private var repsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-Rep Breakdown")
                .font(.headline)
                .foregroundStyle(.white)

            let sorted = session.reps.sorted { $0.repNumber < $1.repNumber }
            ForEach(sorted, id: \.repNumber) { rep in
                HStack {
                    Text("#\(rep.repNumber)")
                        .font(.callout.monospacedDigit().bold())
                        .foregroundStyle(coral)
                        .frame(width: 36, alignment: .leading)

                    Text(String(format: "%.1fs", rep.durationSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 44)

                    depthBar(rep)

                    Spacer()

                    if rep.shoulderAsymmetry > 0.04 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var exportButton: some View {
        Button {
            let json = SessionExporter.toJSON(session: session)
            UIPasteboard.general.string = json
            copiedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copiedToast = false
            }
        } label: {
            Label("Copy for AI Coach", systemImage: "doc.on.clipboard")
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.bottom, 20)
    }

    // MARK: - Helpers

    private func scoreRow(_ label: String, _ value: Int?) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            if let value {
                Text("\(value)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(scoreColor(value))
            } else {
                Text("—")
                    .font(.title2.bold())
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    private func metricPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func depthBar(_ rep: PushupRepRecord) -> some View {
        let maxDepth = session.reps.map(\.depthScreenSpace).max() ?? 1
        let ratio = maxDepth > 0 ? rep.depthScreenSpace / maxDepth : 0

        return GeometryReader { geo in
            RoundedRectangle(cornerRadius: 3)
                .fill(coral.opacity(0.7))
                .frame(width: max(4, geo.size.width * ratio))
        }
        .frame(height: 8)
    }

    private func scoreColor(_ value: Int) -> Color {
        if value >= 80 { return .green }
        if value >= 60 { return .yellow }
        return coral
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}
