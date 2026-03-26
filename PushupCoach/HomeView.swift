import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \PushupSession.startedAt, order: .reverse, animation: .default)
    private var sessions: [PushupSession]

    @State private var showWorkout = false

    private var totalReps: Int { sessions.reduce(0) { $0 + $1.repCount } }
    private var totalSessions: Int { sessions.count }
    private var avgScore: Int? {
        let scored = sessions.compactMap(\.compositeScore)
        guard !scored.isEmpty else { return nil }
        return scored.reduce(0, +) / scored.count
    }
    private var bestRepCount: Int { sessions.map(\.repCount).max() ?? 0 }
    private var bestScore: Int? { sessions.compactMap(\.compositeScore).max() }
    private var latestInsights: [String] { sessions.first?.quickCoachInsights ?? [] }
    private var currentStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        let cal = Calendar.current
        var streak = 0
        var checkDate = cal.startOfDay(for: Date())
        let sessionDays = Set(sessions.map { cal.startOfDay(for: $0.startedAt) })
        if !sessionDays.contains(checkDate) {
            guard let prev = cal.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            checkDate = prev
        }
        while sessionDays.contains(checkDate) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }
        return streak
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, NKSpacing.xl)
                        .padding(.top, NKSpacing.lg)

                    if sessions.isEmpty {
                        firstTimeHero
                            .padding(.horizontal, NKSpacing.xl)
                            .padding(.top, NKSpacing.section)
                    } else {
                        heroMetrics
                            .padding(.horizontal, NKSpacing.xl)
                            .padding(.top, NKSpacing.xxxl)

                        weeklyCalibration
                            .padding(.horizontal, NKSpacing.xl)
                            .padding(.top, NKSpacing.section)

                        statsGrid
                            .padding(.horizontal, NKSpacing.xl)
                            .padding(.top, NKSpacing.lg)
                    }

                    startButton
                        .padding(.horizontal, NKSpacing.xl)
                        .padding(.top, NKSpacing.section)

                    if !sessions.isEmpty {
                        recentSessions
                            .padding(.horizontal, NKSpacing.xl)
                            .padding(.top, NKSpacing.section)

                        coachSnapshot
                            .padding(.horizontal, NKSpacing.xl)
                            .padding(.top, NKSpacing.section)
                    }

                    setupTips
                        .padding(.horizontal, NKSpacing.xl)
                        .padding(.top, NKSpacing.section)
                        .padding(.bottom, NKSpacing.section)
                }
            }
            .nkPageBackground()
            .fullScreenCover(isPresented: $showWorkout) {
                Phase0TestView()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("PushX")
                .font(.system(size: 24, weight: .black))
                .tracking(3)
                .foregroundStyle(Color.nkPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("STREAK")
                    .font(.nkLabelXS)
                    .tracking(1.2)
                    .foregroundStyle(Color.nkOutline)
                Text("\(currentStreak) days")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.nkPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, NKSpacing.md)
            .padding(.vertical, NKSpacing.sm)
            .background(Color.nkSurfaceContainerLow)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .nkSelectiveGlass(cornerRadius: 12, tint: .nkPrimary)
        }
    }

    // MARK: - First Time Hero

    private var firstTimeHero: some View {
        VStack(alignment: .leading, spacing: NKSpacing.lg) {
            Text("READY TO CALIBRATE")
                .nkPrimaryLabel()

            Text("Your First\nSession Awaits")
                .font(.nkHeadlineMD)
                .tracking(-0.5)
                .foregroundStyle(Color.nkOnSurface)

            Text("PushX uses your camera to track pushup form in real-time. No data leaves your device.")
                .font(.nkBodyMD)
                .foregroundStyle(Color.nkOnSurfaceVariant)
                .lineSpacing(4)
                .padding(.top, NKSpacing.micro)

            HStack(spacing: NKSpacing.md) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(Color.nkPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.nkPrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("On-Device AI")
                        .font(.nkTitleSM)
                        .foregroundStyle(Color.nkOnSurface)
                    Text("PushXPose detection — zero cloud processing")
                        .font(.nkLabelXS)
                        .foregroundStyle(Color.nkOnSurfaceVariant)
                }
            }
            .padding(NKSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nkCardElevated()
            .nkSelectiveGlass(cornerRadius: 12, tint: .nkPrimary)
        }
    }

    // MARK: - Hero Metrics (Kinetic Asymmetry)

    private var heroMetrics: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: NKSpacing.micro) {
                Text("CURRENT STREAK")
                    .nkTechnicalLabel()
                HStack(alignment: .firstTextBaseline, spacing: NKSpacing.sm) {
                    Text("\(currentStreak)")
                        .font(.system(size: 56, weight: .heavy))
                        .foregroundStyle(Color.nkPrimary)
                        .monospacedDigit()
                    Text("Days")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.nkPrimaryDim)
                        .textCase(.uppercase)
                        .tracking(-0.5)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Current streak: \(currentStreak) days")
            }

            Spacer()

            VStack(alignment: .trailing, spacing: NKSpacing.micro) {
                Text("PERSONAL BEST")
                    .nkTechnicalLabel()
                HStack(alignment: .firstTextBaseline, spacing: NKSpacing.micro) {
                    Text("\(bestRepCount)")
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.nkOnSurface)
                    Text("REPS")
                        .font(.nkLabelXS)
                        .foregroundStyle(Color.nkOutline)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Personal best: \(bestRepCount) reps")
            }
        }
    }

    // MARK: - Weekly Calibration

    private var weeklyCalibration: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -mondayOffset, to: today) ?? today
        let sessionDays = Set(sessions.map { cal.startOfDay(for: $0.startedAt) })
        let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

        return VStack(spacing: NKSpacing.lg) {
            HStack {
                Text("WEEKLY CALIBRATION")
                    .nkPrimaryLabel()
                Spacer()
                Text(monday.formatted(.dateTime.month(.abbreviated).day()) + " – " + today.formatted(.dateTime.month(.abbreviated).day()))
                    .nkTechnicalLabel()
            }

            HStack {
                ForEach(0..<7, id: \.self) { i in
                    let day = cal.date(byAdding: .day, value: i, to: monday) ?? today
                    let isToday = cal.isDate(day, inSameDayAs: today)
                    let hasSession = sessionDays.contains(cal.startOfDay(for: day))
                    let isFuture = day > today

                    VStack(spacing: NKSpacing.sm) {
                        Circle()
                            .fill(hasSession ? Color.nkPrimary : (isFuture ? Color.clear : Color.nkSurfaceContainerHighest))
                            .frame(width: 12, height: 12)
                            .shadow(color: hasSession ? Color.nkPrimary.opacity(0.6) : .clear, radius: 6)
                            .overlay {
                                if isToday && !hasSession {
                                    Circle()
                                        .stroke(Color.nkPrimary.opacity(0.3), lineWidth: 1)
                                }
                            }
                        Text(dayLabels[i])
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(isToday ? Color.nkPrimary : Color.nkOutline)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(dayLabels[i]): \(hasSession ? "completed" : "no workout")")
                }
            }
        }
        .padding(NKSpacing.xl)
        .background(Color.nkSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.nkOutlineVariant.opacity(0.1), lineWidth: 1)
        )
        .nkSelectiveGlass(cornerRadius: 12)
    }

    // MARK: - Stats Grid (Bento)

    private var statsGrid: some View {
        HStack(spacing: NKSpacing.lg) {
            statCard("SESSIONS", "\(totalSessions)")
            if let avg = avgScore {
                statCard("AVG FORM", "\(avg)", valueColor: .nkScoreColor(avg))
            } else {
                statCard("AVG FORM", "—")
            }
        }
    }

    private func statCard(_ label: String, _ value: String, valueColor: Color = .nkOnSurface) -> some View {
        VStack(alignment: .leading, spacing: NKSpacing.sm) {
            Text(label)
                .font(.nkLabelXS)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.nkOnSurfaceVariant)
            Text(value)
                .font(.system(size: 28, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NKSpacing.xl)
        .nkCardElevated()
        .nkSelectiveGlass(cornerRadius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Start Button (Kinetic CTA)

    private var startButton: some View {
        Button {
            showWorkout = true
        } label: {
            HStack(spacing: NKSpacing.md) {
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("Start Session")
            }
        }
        .buttonStyle(NKPrimaryButtonStyle())
        .accessibilityHint("Opens the camera for a pushup workout session")
    }

    // MARK: - Recent Sessions

    private var recentSessions: some View {
        VStack(spacing: NKSpacing.lg) {
            HStack {
                Text("RECENT SESSIONS")
                    .font(.nkLabelSM)
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.nkOutline)
                Spacer()
                NavigationLink {
                    HistoryView()
                } label: {
                    Text("VIEW ALL")
                        .font(.nkLabelSM)
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.nkPrimary)
                }
                .accessibilityLabel("View all workout history")
            }

            VStack(spacing: NKSpacing.md) {
                ForEach(sessions.prefix(3), id: \.id) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sessionRow(_ session: PushupSession) -> some View {
        HStack(spacing: NKSpacing.lg) {
            Rectangle()
                .fill(session.compositeScore.map { Color.nkScoreColor($0) } ?? Color.nkOutlineVariant.opacity(0.4))
                .frame(width: 3, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: NKSpacing.micro) {
                Text("\(session.repCount) Reps")
                    .font(.nkTitleSM)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.nkOnSurface)
                Text(session.relativeDayLabel)
                    .font(.nkLabelSM)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.nkOnSurfaceVariant)
                Text(session.timeLabel)
                    .font(.nkLabelXS)
                    .foregroundStyle(Color.nkOutline)
            }

            Spacer()

            if let score = session.compositeScore {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.nkScoreColor(score))
                    Text(Color.nkScoreLabel(score))
                        .font(.nkLabelXS)
                        .foregroundStyle(Color.nkOnSurfaceVariant)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Form score \(score), \(Color.nkScoreLabel(score))")
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.nkOutline)
        }
        .padding(.horizontal, NKSpacing.lg)
        .padding(.vertical, NKSpacing.md)
        .background(Color.nkSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .nkSelectiveGlass(cornerRadius: 8)
    }

    private var coachSnapshot: some View {
        VStack(alignment: .leading, spacing: NKSpacing.lg) {
            HStack {
                Text("QUICK COACH")
                    .nkPrimaryLabel()
                Spacer()
                if let bestScore {
                    Text("BEST SCORE \(bestScore)")
                        .nkTechnicalLabel()
                }
            }

            VStack(alignment: .leading, spacing: NKSpacing.md) {
                ForEach(latestInsights, id: \.self) { insight in
                    HStack(alignment: .top, spacing: NKSpacing.md) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.nkPrimary)
                            .frame(width: 16)
                        Text(insight)
                            .font(.nkBodyMD)
                            .foregroundStyle(Color.nkOnSurface)
                    }
                }
            }
        }
        .padding(NKSpacing.xl)
        .nkCardElevated()
        .nkSelectiveGlass(cornerRadius: 12, tint: .nkPrimary)
    }

    // MARK: - Setup Tips

    private var setupTips: some View {
        VStack(alignment: .leading, spacing: NKSpacing.lg) {
            HStack(spacing: NKSpacing.md) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(Color.nkPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.nkPrimary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("SETUP PROTOCOL")
                    .nkPrimaryLabel()
            }

            VStack(alignment: .leading, spacing: NKSpacing.md) {
                tipRow(icon: "light.max", text: "Light the scene so your upper body is easy to see")
                tipRow(icon: "iphone", text: "Place your phone upright against a wall")
                tipRow(icon: "figure.strengthtraining.traditional", text: "Step back into plank, 2–3 feet away")
            }
        }
        .padding(NKSpacing.xl)
        .background(Color.nkSurfaceContainerHighest.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.nkPrimary.opacity(0.1), lineWidth: 1)
        )
        .nkSelectiveGlass(cornerRadius: 12, tint: .nkPrimary)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: NKSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.nkOnSurfaceVariant)
                .frame(width: 20)
            Text(text)
                .font(.nkBodyMD)
                .foregroundStyle(Color.nkOnSurfaceVariant)
        }
    }
}
