import SwiftUI
import SwiftData
import os
import UIKit

@main
struct PushXApp: App {
    let modelContainer: ModelContainer

    init() {
        let logger = Logger(subsystem: "com.pushx", category: "AppStartup")
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Color.nkSurface)
        tabAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.nkPrimary)
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Color.nkPrimary)]
        tabAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color.nkOutline)
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(Color.nkOutline)]
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        do {
            modelContainer = try ModelContainer(for: PushupSession.self, PushupRepRecord.self)
        } catch {
            logger.error("ModelContainer init failed: \(error.localizedDescription) — falling back to in-memory store for safety")
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                modelContainer = try ModelContainer(
                    for: PushupSession.self, PushupRepRecord.self,
                    configurations: config
                )
            } catch {
                fatalError("Cannot create ModelContainer fallback: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
        }
        .modelContainer(modelContainer)
    }
}

private struct AppShellView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            TabView {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }

                NavigationStack {
                    HistoryView()
                }
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

                NavigationStack {
                    AICoachView()
                }
                .tabItem {
                    Label("AI Coach", systemImage: "sparkles")
                }
            }
            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .tint(.nkPrimary)
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.25)) {
                showSplash = false
            }
        }
    }
}

private struct SplashScreenView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.nkSurface, Color.nkSurfaceContainerLow],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: NKSpacing.lg) {
                Image("SplashIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: NKSpacing.section * 3.2, height: NKSpacing.section * 3.2)
                    .clipShape(RoundedRectangle(cornerRadius: NKSpacing.xxl, style: .continuous))
                    .shadow(color: Color.nkPrimary.opacity(0.14), radius: NKSpacing.xl, y: NKSpacing.sm)

                VStack(spacing: NKSpacing.xs) {
                    Text("PushX")
                        .font(.system(size: 28, weight: .black))
                        .tracking(2.4)
                        .foregroundStyle(Color.nkOnSurface)
                    Text("AI coach to crush 100 pushups")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Color.nkOnSurfaceVariant)
                }
            }
        }
    }
}

struct AICoachView: View {
    @Query(sort: \PushupSession.startedAt, order: .reverse) private var sessions: [PushupSession]
    @State private var copiedToast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NKSpacing.lg) {
                VStack(alignment: .leading, spacing: NKSpacing.md) {
                    Text("AI COACH")
                        .nkPrimaryLabel()

                    VStack(alignment: .leading, spacing: NKSpacing.sm) {
                        Text("Coming Soon")
                            .font(.nkHeadlineSM)
                            .foregroundStyle(Color.nkOnSurface)

                        Text("GPT-powered AI coach is launching soon. Copy one session or your full history here, then paste it into ChatGPT to get coached.")
                            .font(.nkBodyMD)
                            .foregroundStyle(Color.nkOnSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(NKSpacing.xl)
                    .nkCardElevated()
                    .nkSelectiveGlass(cornerRadius: 12, tint: .nkPrimary)
                }

                Button {
                    UIPasteboard.general.string = SessionExporter.toJSON(sessions: Array(sessions))
                    showCopiedToast()
                } label: {
                    Label("Copy All Sessions", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(NKPrimaryButtonStyle())

                if sessions.isEmpty {
                    VStack(alignment: .leading, spacing: NKSpacing.md) {
                        Text("No sessions yet")
                            .font(.nkHeadlineSM)
                            .foregroundStyle(Color.nkOnSurface)
                        Text("Complete a set first, then come back here to copy your session data.")
                            .font(.nkBodyMD)
                            .foregroundStyle(Color.nkOnSurfaceVariant)
                    }
                    .padding(NKSpacing.xl)
                    .nkCardElevated()
                    .nkSelectiveGlass(cornerRadius: 12, tint: .nkPrimary)
                } else {
                    ForEach(sessions, id: \.id) { session in
                        VStack(alignment: .leading, spacing: NKSpacing.sm) {
                            Text(session.relativeDayLabel)
                                .font(.nkTitleSM)
                                .foregroundStyle(Color.nkOnSurface)
                            Text(session.timeLabel)
                                .font(.nkLabelXS)
                                .foregroundStyle(Color.nkOutline)
                            Text("\(session.repCount) reps")
                                .nkTechnicalLabel()

                            Button {
                                UIPasteboard.general.string = SessionExporter.toJSON(session: session)
                                showCopiedToast()
                            } label: {
                                Text("Copy Session")
                            }
                            .buttonStyle(NKSecondaryButtonStyle())
                        }
                        .padding(NKSpacing.xl)
                        .nkCardElevated()
                        .nkSelectiveGlass(cornerRadius: 12, tint: .nkPrimary)
                    }
                }
            }
            .padding(.horizontal, NKSpacing.xl)
            .padding(.vertical, NKSpacing.lg)
        }
        .nkPageBackground()
        .navigationTitle("AI Coach")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if copiedToast {
                Text("COPIED TO CLIPBOARD")
                    .font(.nkLabelSM)
                    .tracking(1.2)
                    .foregroundStyle(Color.nkOnPrimary)
                    .padding(.horizontal, NKSpacing.xl)
                    .padding(.vertical, NKSpacing.md)
                    .background(Color.nkPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: NKSpacing.sm))
                    .padding(.bottom, NKSpacing.xxl)
                    .transition(.nkSlideUp)
            }
        }
    }

    private func showCopiedToast() {
        copiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            copiedToast = false
        }
    }
}
