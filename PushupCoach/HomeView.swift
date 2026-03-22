import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \PushupSession.startedAt, order: .reverse, animation: .default)
    private var sessions: [PushupSession]

    @State private var showWorkout = false

    private let coral = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 56))
                        .foregroundStyle(coral)

                    Text("PushX")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)

                    Text("AI-powered pushup form tracking")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.6))

                    if let last = sessions.first {
                        lastSessionCard(last)
                    }

                    statsRow

                    Button {
                        showWorkout = true
                    } label: {
                        Text("Start Pushups")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(coral)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 40)

                    NavigationLink {
                        HistoryView()
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("View History")
                        }
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 40)

                    setupTips
                        .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .fullScreenCover(isPresented: $showWorkout) {
                Phase0TestView()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private func lastSessionCard(_ session: PushupSession) -> some View {
        VStack(spacing: 8) {
            Text("Last Workout")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.5))

            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text("\(session.repCount)")
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(.white)
                    Text("reps")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }

                if let score = session.compositeScore {
                    VStack(spacing: 2) {
                        Text("\(score)")
                            .font(.title.bold().monospacedDigit())
                            .foregroundStyle(scoreColor(score))
                        Text("form")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                VStack(spacing: 2) {
                    Text(session.startedAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.callout.bold())
                        .foregroundStyle(.white.opacity(0.8))
                    Text("date")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
    }

    private var statsRow: some View {
        let totalReps = sessions.reduce(0) { $0 + $1.repCount }
        let totalSessions = sessions.count
        let avgScore: Int? = {
            let scored = sessions.compactMap(\.compositeScore)
            guard !scored.isEmpty else { return nil }
            return scored.reduce(0, +) / scored.count
        }()

        return HStack(spacing: 16) {
            statPill("\(totalSessions)", "sets")
            statPill("\(totalReps)", "total reps")
            if let avg = avgScore {
                statPill("\(avg)", "avg form")
            }
        }
        .padding(.horizontal, 20)
    }

    private func statPill(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var setupTips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Lean phone against a wall, screen facing you", systemImage: "iphone")
            Label("Portrait orientation (tall, not sideways)", systemImage: "arrow.up")
            Label("Step back 2–3 feet in pushup position", systemImage: "figure.strengthtraining.traditional")
            Label("Good lighting, upper body in view", systemImage: "light.max")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.5))
    }

    private func scoreColor(_ value: Int) -> Color {
        if value >= 80 { return .green }
        if value >= 60 { return .yellow }
        return coral
    }
}
