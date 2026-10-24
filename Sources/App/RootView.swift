import SwiftUI

enum AppTab: Int, CaseIterable {
    case dashboard, coach, insights, live, history

    var title: String {
        switch self {
        case .dashboard: return "Today"
        case .coach: return "Coach"
        case .insights: return "Insights"
        case .live: return "Live"
        case .history: return "History"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "chart.pie.fill"
        case .coach: return "sparkles"
        case .insights: return "chart.line.uptrend.xyaxis"
        case .live: return "antenna.radiowaves.left.and.right"
        case .history: return "clock.fill"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedTab: AppTab = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["NW_TAB"] == "live" { return .live }
        #endif
        return .dashboard
    }()
    @State private var showCamera = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if model.profile.hasCompletedOnboarding {
                    mainInterface
                } else {
                    OnboardingView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea(.keyboard)
    }

    private var mainInterface: some View {
        ZStack(alignment: .bottom) {
            // Full-screen sizing + background layer. A non-ignoring clear color
            // forces the ZStack to claim the whole screen (ignoresSafeArea views
            // don't contribute to layout size, which was collapsing the stack).
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
                .overlay(
                    RadialGradient(colors: [Theme.calories.opacity(0.14), .clear],
                                   center: .topTrailing, startRadius: 10, endRadius: 420)
                        .ignoresSafeArea()
                )

            // Active tab content fills the whole area.
            Group {
                switch selectedTab {
                case .dashboard: DashboardView(showCamera: $showCamera)
                case .coach: CoachView(speech: model.speech)
                case .insights: InsightsView()
                case .live: LiveView(sync: model.sync)
                case .history: HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Tab bar pinned to the bottom.
            CustomTabBar(selectedTab: $selectedTab, showCamera: $showCamera)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fullScreenCover(isPresented: $showCamera) {
            CameraScanView()
                .environmentObject(model)
        }
    }
}

/// Floating glass tab bar with a prominent central scan button.
struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    @Binding var showCamera: Bool

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.dashboard)
            tabButton(.coach)
            tabButton(.insights)

            // Central scan button
            Button {
                showCamera = true
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.calories, Theme.protein],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)
                        .shadow(color: Theme.calories.opacity(0.5), radius: 14, y: 6)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .offset(y: -16)
            .accessibilityLabel("Scan a meal")

            tabButton(.live)
            tabButton(.history)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Theme.card.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selectedTab == tab ? Theme.textPrimary : Theme.textTertiary)
            .frame(maxWidth: .infinity)
        }
    }
}
