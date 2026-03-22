import SwiftUI

struct SessionDetailView: View {
    let session: PushupSession
    @State private var copiedToast = false

    var body: some View {
        ScrollView {
            VStack(spacing: NKSpacing.section) {
                heroSection
                if session.hasScores {
                    kineticMetricsRow
                    scoresBentoGrid
                } else {
                    noScoresSection
                }
                if !session.improvements.isEmpty {
                    improvementsSection
                }
                if !session.reps.isEmpty {
                    repsSection
                }
                exportSection
            }
            .padding(.horizontal, NKSpacing.xl)
            .padding(.top, NKSpacing.xxxl)
            .padding(.bottom, NKSpacing.section)
        }
        .nkPageBackground()
        .navigationTitle("Session Detail")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if copiedToast {
                toastView
            }
        }
        .animation(.easeInOut(duration: 0.25), value: copiedToast)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: NKSpacing.sm) {
            Text("SESSION DETAIL")
                .nkPrimaryLabel()
                .accessibilityAddTraits(.isHeader)

            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.nkBodyMD)
                .foregroundStyle(Color.nkOnSurfaceVariant)
                .accessibilityLabel("Session date: \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")

            HStack(spacing: NKSpacing.md) {
                metricPill("DURATION", formatDuration(session.durationSeconds))
                metricPill("PROVIDER", session.providerType.uppercased())
                if let avg = session.averageRepDuration {
                    metricPill("AVG/REP", String(format: "%.1fs", avg))
                }
            }
            .padding(.top, NKSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Kinetic Asymmetry: Rep Count + Form Score

    private var kineticMetricsRow: some View {
        HStack(alignment: .top, spacing: NKSpacing.lg) {
            // Left: massive rep count
            VStack(alignment: .leading, spacing: NKSpacing.micro) {
                Text("REPS")
                    .nkTechnicalLabel()

                Text("\(session.repCount)")
                    .font(.nkDisplayLG)
                    .foregroundStyle(Color.nkOnSurface)
                    .nkAmbientGlow()
                    .accessibilityLabel("\(session.repCount) reps")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: composite score
            if let composite = session.compositeScore {
                VStack(alignment: .trailing, spacing: NKSpacing.micro) {
                    Text("FORM SCORE")
                        .nkTechnicalLabel()

                    Text("\(composite)")
                        .font(.nkDisplayLG)
                        .monospacedDigit()
                        .foregroundStyle(Color.nkScoreColor(composite))
                        .nkAmbientGlow(color: Color.nkScoreColor(composite))
                        .accessibilityLabel("Form score \(composite)")

                    Text(Color.nkScoreLabel(composite).uppercased())
                        .font(.nkLabelXS)
                        .tracking(1)
                        .foregroundStyle(Color.nkScoreColor(composite))
                        .accessibilityLabel(Color.nkScoreLabel(composite))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(NKSpacing.xl)
        .nkCardElevated()
        .nkAmbientGlow()
    }

    // MARK: - Scores Bento Grid

    private var scoresBentoGrid: some View {
        VStack(alignment: .leading, spacing: NKSpacing.md) {
            Text("SCORE BREAKDOWN")
                .nkTechnicalLabel()
                .padding(.leading, NKSpacing.micro)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: NKSpacing.md),
                          GridItem(.flexible(), spacing: NKSpacing.md)],
                spacing: NKSpacing.md
            ) {
                scoreCard("Depth", session.depthScore)
                scoreCard("Alignment", session.alignmentScore)
                scoreCard("Consistency", session.consistencyScore)
                durationCard
            }
        }
    }

    private func scoreCard(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: NKSpacing.sm) {
            Text(label.uppercased())
                .font(.nkLabelXS)
                .tracking(1)
                .foregroundStyle(Color.nkOnSurfaceVariant)

            if let value {
                Text("\(value)")
                    .font(.nkHeadlineMD)
                    .monospacedDigit()
                    .foregroundStyle(Color.nkScoreColor(value))
                    .accessibilityLabel("\(label) score \(value)")

                Text(Color.nkScoreLabel(value))
                    .font(.nkLabelXS)
                    .foregroundStyle(Color.nkScoreColor(value).opacity(0.8))

                scoreBar(value: value)
            } else {
                Text("—")
                    .font(.nkHeadlineMD)
                    .foregroundStyle(Color.nkOnSurfaceVariant.opacity(0.4))
                    .accessibilityLabel("\(label) score not available")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NKSpacing.lg)
        .nkCard()
    }

    private func scoreBar(value: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.nkSurfaceContainerHighest)

                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [Color.nkScoreColor(value), Color.nkScoreColor(value).opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(value) / 100.0)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: NKSpacing.sm) {
            Text("DURATION")
                .font(.nkLabelXS)
                .tracking(1)
                .foregroundStyle(Color.nkOnSurfaceVariant)

            Text(formatDuration(session.durationSeconds))
                .font(.nkHeadlineMD)
                .monospacedDigit()
                .foregroundStyle(Color.nkOnSurface)
                .accessibilityLabel("Session duration \(formatDuration(session.durationSeconds))")

            if let avg = session.averageRepDuration {
                Text(String(format: "%.1fs avg", avg))
                    .font(.nkLabelXS)
                    .foregroundStyle(Color.nkOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NKSpacing.lg)
        .nkCard()
    }

    // MARK: - No Scores

    private var noScoresSection: some View {
        VStack(spacing: NKSpacing.sm) {
            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.nkHeadlineSM)
                .foregroundStyle(Color.nkOnSurfaceVariant.opacity(0.5))

            Text("Not enough reps for scoring")
                .font(.nkBodyMD)
                .foregroundStyle(Color.nkOnSurfaceVariant)

            Text("Complete 2+ reps to unlock form analysis")
                .font(.nkLabelXS)
                .foregroundStyle(Color.nkOutline)
        }
        .frame(maxWidth: .infinity)
        .padding(NKSpacing.xxl)
        .nkCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Not enough reps for scoring. Complete 2 or more reps to unlock form analysis.")
    }

    // MARK: - Improvements

    private var improvementsSection: some View {
        VStack(alignment: .leading, spacing: NKSpacing.md) {
            Text("IMPROVEMENT AREAS")
                .nkTechnicalLabel()
                .padding(.leading, NKSpacing.micro)

            ForEach(Array(session.improvements.enumerated()), id: \.offset) { idx, text in
                HStack(alignment: .top, spacing: NKSpacing.md) {
                    Text("\(idx + 1)")
                        .font(.nkTitleSM.italic())
                        .foregroundStyle(Color.nkPrimary)
                        .frame(width: 24, alignment: .trailing)
                        .accessibilityHidden(true)

                    Text(text)
                        .font(.nkBodyMD)
                        .foregroundStyle(Color.nkOnSurface.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(NKSpacing.lg)
                .nkCard()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Suggestion \(idx + 1): \(text)")
            }
        }
    }

    // MARK: - Per-Rep Training Log

    private var repsSection: some View {
        VStack(alignment: .leading, spacing: NKSpacing.lg) {
            Text("PER-REP BREAKDOWN")
                .nkTechnicalLabel()
                .padding(.leading, NKSpacing.micro)

            let sorted = session.reps.sorted { $0.repNumber < $1.repNumber }
            ForEach(sorted, id: \.repNumber) { rep in
                repRow(rep)
            }
        }
    }

    private func repRow(_ rep: PushupRepRecord) -> some View {
        HStack(spacing: NKSpacing.md) {
            Text(String(format: "%02d", rep.repNumber))
                .font(.nkTitleSM.monospacedDigit())
                .foregroundStyle(Color.nkPrimary)
                .frame(width: 28, alignment: .leading)
                .accessibilityLabel("Rep \(rep.repNumber)")

            Text(String(format: "%.1fs", rep.durationSeconds))
                .font(.nkLabelSM.monospacedDigit())
                .foregroundStyle(Color.nkOnSurfaceVariant)
                .frame(width: 40, alignment: .trailing)
                .accessibilityLabel(String(format: "%.1f seconds", rep.durationSeconds))

            depthBar(rep)
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            if rep.shoulderAsymmetry > 0.04 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.nkLabelXS)
                    .foregroundStyle(Color.nkError)
                    .accessibilityLabel("Shoulder asymmetry warning")
            }
        }
        .padding(.horizontal, NKSpacing.lg)
        .padding(.vertical, NKSpacing.md)
        .background(Color.nkSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Export

    private var exportSection: some View {
        Button {
            let json = SessionExporter.toJSON(session: session)
            UIPasteboard.general.string = json
            copiedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copiedToast = false
            }
        } label: {
            Label("Copy for AI Coach", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(NKSecondaryButtonStyle())
        .accessibilityHint("Copies session data as JSON to clipboard")
    }

    // MARK: - Toast

    private var toastView: some View {
        HStack(spacing: NKSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.nkBodyMD)
            Text("Copied to clipboard")
                .font(.nkLabelSM)
                .tracking(0.8)
        }
        .foregroundStyle(Color.nkOnPrimaryContainer)
        .padding(.horizontal, NKSpacing.xl)
        .padding(.vertical, NKSpacing.md)
        .background(Color.nkPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .padding(.bottom, NKSpacing.xxl)
        .accessibilityLabel("Copied to clipboard")
    }

    // MARK: - Helpers

    private func metricPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: NKSpacing.micro) {
            Text(value)
                .font(.nkLabelSM.monospacedDigit())
                .foregroundStyle(Color.nkOnSurface)
            Text(label)
                .font(.nkLabelXS)
                .tracking(0.8)
                .foregroundStyle(Color.nkOutline)
        }
        .padding(.horizontal, NKSpacing.md)
        .padding(.vertical, NKSpacing.sm)
        .background(Color.nkSurfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func depthBar(_ rep: PushupRepRecord) -> some View {
        let maxDepth = session.reps.map(\.depthScreenSpace).max() ?? 1
        let ratio = maxDepth > 0 ? rep.depthScreenSpace / maxDepth : 0

        return GeometryReader { geo in
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [.nkPrimary, .nkPrimaryDim],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(4, geo.size.width * ratio))
        }
        .frame(height: 6)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}
