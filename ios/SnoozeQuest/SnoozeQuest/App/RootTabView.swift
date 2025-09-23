//
//  RootTabView.swift
//  SnoozeQuest
//

import SwiftUI

struct RootTabView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isShowingOnboarding = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            GoalsView()
                .tabItem {
                    Label("Goals", systemImage: "target")
                }

            LeaderboardView()
                .tabItem {
                    Label("Leaderboard", systemImage: "list.number")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onAppear {
            isShowingOnboarding = !hasCompletedOnboarding
        }
        .fullScreenCover(isPresented: $isShowingOnboarding) {
            OnboardingFlowView {
                hasCompletedOnboarding = true
                isShowingOnboarding = false
            }
        }
    }
}

#Preview {
    RootTabView()
}
