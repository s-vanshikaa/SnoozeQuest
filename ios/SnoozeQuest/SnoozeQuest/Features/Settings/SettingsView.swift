//
//  SettingsView.swift
//  SnoozeQuest
//

import SwiftUI

struct SettingsView: View {
    @State private var isShowingOnboarding = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Health") {
                    LabeledContent("Apple Health", value: "Not Connected")
                    LabeledContent("Last Sync", value: "Never")
                    Button("Sync Now") {}
                        .disabled(true)
                }
                .listRowBackground(SQColor.surface)

                Section("Notifications") {
                    LabeledContent("Notifications", value: "Off")
                }
                .listRowBackground(SQColor.surface)

                Section {
                    Button("Replay Onboarding") {
                        isShowingOnboarding = true
                    }
                    .tint(SQColor.skyBlue)
                } footer: {
                    Text("Replays the first-launch welcome and setup experience.")
                }
                .listRowBackground(SQColor.surface)
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(SQColor.background)
            .fullScreenCover(isPresented: $isShowingOnboarding) {
                OnboardingFlowView {
                    isShowingOnboarding = false
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
