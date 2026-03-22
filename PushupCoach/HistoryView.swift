import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \PushupSession.startedAt, order: .reverse)
    private var sessions: [PushupSession]

    @Environment(\.modelContext) private var modelContext
    @State private var copiedAllToast = false

    private let coral = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if sessions.isEmpty {
                    emptyState
                } else {
                    FormTrendChart(sessions: sessions)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                    if sessions.count >= 2 {
                        exportAllButton
                    }

                    LazyVStack(spacing: 10) {
                        ForEach(sessions, id: \.id) { session in
                            NavigationLink(value: session.id) {
                                sessionRow(session)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    SessionStore.delete(session: session, context: modelContext)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { sessionID in
            if let session = sessions.first(where: { $0.id == sessionID }) {
                SessionDetailView(session: session)
            }
        }
        .overlay(alignment: .bottom) {
            if copiedAllToast {
                Text("All sessions copied")
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
        .animation(.easeInOut(duration: 0.25), value: copiedAllToast)
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 80)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48))
                .foregroundStyle(coral.opacity(0.5))
            Text("No workouts yet")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Start your first pushup set!")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func sessionRow(_ session: PushupSession) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text("\(session.repCount) reps")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))

                    Text(session.providerType)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            if let score = session.compositeScore {
                Text("\(score)")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(scoreColor(score))
            } else {
                Text("—")
                    .font(.title2.bold())
                    .foregroundStyle(.white.opacity(0.3))
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var exportAllButton: some View {
        Button {
            let json = SessionExporter.toJSON(sessions: Array(sessions))
            UIPasteboard.general.string = json
            copiedAllToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copiedAllToast = false
            }
        } label: {
            Label("Export All for AI Coach", systemImage: "doc.on.clipboard")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func scoreColor(_ value: Int) -> Color {
        if value >= 80 { return .green }
        if value >= 60 { return .yellow }
        return coral
    }
}
