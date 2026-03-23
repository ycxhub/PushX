import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \PushupSession.startedAt, order: .reverse)
    private var sessions: [PushupSession]

    @Environment(\.modelContext) private var modelContext
    @State private var copiedAllToast = false

    var body: some View {
        ScrollView {
            VStack(spacing: NKSpacing.lg) {
                if sessions.isEmpty {
                    emptyState
                } else {
                    headerSection

                    FormTrendChart(sessions: sessions)
                        .padding(.horizontal, NKSpacing.micro)
                        .padding(.top, NKSpacing.sm)

                    if sessions.count >= 2 {
                        exportAllButton
                    }

                    sessionsList
                }
            }
            .padding(.horizontal, NKSpacing.xl)
            .padding(.vertical, NKSpacing.lg)
        }
        .nkPageBackground()
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { sessionID in
            if let session = sessions.first(where: { $0.id == sessionID }) {
                SessionDetailView(session: session)
            }
        }
        .overlay(alignment: .bottom) {
            if copiedAllToast {
                toastView
            }
        }
        .animation(.easeInOut(duration: 0.25), value: copiedAllToast)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: NKSpacing.xs) {
            Text("TRAINING LOG")
                .nkTechnicalLabel()

            Text("\(sessions.count) Sessions")
                .font(.nkHeadlineMD)
                .foregroundStyle(Color.nkOnSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sessions.count) training sessions")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: NKSpacing.lg) {
            Spacer(minLength: 80)

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(Color.nkPrimary.opacity(0.4))
                .nkAmbientGlow(color: .nkPrimary, radius: 40, opacity: 0.12)
                .padding(.bottom, NKSpacing.sm)

            Text("NO DATA YET")
                .nkPrimaryLabel()

            Text("Begin Calibration")
                .font(.nkHeadlineMD)
                .foregroundStyle(Color.nkOnSurface)

            Text("Complete your first pushup set to populate the training log.")
                .font(.nkBodyMD)
                .foregroundStyle(Color.nkOnSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No workouts yet. Complete your first pushup set to see history.")
    }

    // MARK: - Sessions List

    private var sessionsList: some View {
        List {
            ForEach(sessions, id: \.id) { session in
                NavigationLink(value: session.id) {
                    sessionRow(session)
                }
                .listRowBackground(Color.nkSurfaceContainerLow)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: NKSpacing.xs, leading: NKSpacing.xl, bottom: NKSpacing.xs, trailing: NKSpacing.xl))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        SessionStore.delete(session: session, context: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: PushupSession) -> some View {
        HStack(spacing: NKSpacing.md) {
            VStack(alignment: .leading, spacing: NKSpacing.xs) {
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.nkTitleSM)
                    .foregroundStyle(Color.nkOnSurface)

                HStack(spacing: NKSpacing.sm) {
                    Text("\(session.repCount) REPS")
                        .nkTechnicalLabel()

                    Text(session.providerType.uppercased())
                        .font(.nkLabelXS)
                        .tracking(0.8)
                        .foregroundStyle(Color.nkOnSurfaceVariant.opacity(0.7))
                        .padding(.horizontal, NKSpacing.sm)
                        .padding(.vertical, NKSpacing.micro)
                        .background(Color.nkSurfaceContainerHighest)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Spacer()

            if let score = session.compositeScore {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)")
                        .font(.nkHeadlineSM.monospacedDigit())
                        .foregroundStyle(Color.nkScoreColor(score))

                    Text(Color.nkScoreLabel(score).uppercased())
                        .font(.nkLabelXS)
                        .tracking(0.8)
                        .foregroundStyle(Color.nkScoreColor(score).opacity(0.7))
                }
            } else {
                Text("—")
                    .font(.nkHeadlineSM)
                    .foregroundStyle(Color.nkOnSurfaceVariant.opacity(0.3))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.nkOutlineVariant)
        }
        .padding(.horizontal, NKSpacing.lg)
        .padding(.vertical, NKSpacing.md)
        .nkCardElevated()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sessionAccessibilityLabel(session))
    }

    // MARK: - Export Button

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
        }
        .buttonStyle(NKGhostButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Export all sessions to clipboard for AI coach analysis")
    }

    // MARK: - Toast

    private var toastView: some View {
        Text("ALL SESSIONS COPIED")
            .font(.nkLabelSM)
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(Color.nkOnPrimary)
            .padding(.horizontal, NKSpacing.xl)
            .padding(.vertical, NKSpacing.md)
            .background(Color.nkPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .nkAmbientGlow(color: .nkPrimary, radius: 24, opacity: 0.2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .padding(.bottom, NKSpacing.xxl)
            .accessibilityLabel("All sessions copied to clipboard")
    }

    // MARK: - Helpers

    private func sessionAccessibilityLabel(_ session: PushupSession) -> String {
        var label = "\(session.repCount) reps on \(session.startedAt.formatted(date: .abbreviated, time: .shortened))"
        if let score = session.compositeScore {
            label += ", score \(score) \(Color.nkScoreLabel(score))"
        }
        return label
    }
}
