//
//  SettingsView.swift
//  SnoozeQuest
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel(
        healthKitService: AppEnvironment.healthKitService,
        notificationService: AppEnvironment.notificationService,
        goalRepository: AppEnvironment.goalRepository
    )
    @State private var isShowingOnboarding = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Health") {
                    LabeledContent("Apple Health", value: viewModel.healthKitStatusText)
                    LabeledContent("Last Sync", value: "Never")
                    if viewModel.healthKitStatus == .notDetermined {
                        Button("Connect Apple Health") {
                            Task { await viewModel.connectAppleHealth() }
                        }
                    } else if viewModel.healthKitStatus == .denied {
                        Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                    Button("Sync Now") {}
                        .disabled(true)
                }
                .listRowBackground(SQColor.surface)

                Section("Notifications") {
                    LabeledContent("Notifications", value: viewModel.notificationStatusText)
                    if viewModel.notificationStatus == .notDetermined {
                        Button("Enable Notifications") {
                            Task { await viewModel.requestNotificationAuthorization() }
                        }
                    } else if viewModel.notificationStatus == .denied {
                        Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                    Toggle("Bedtime Reminder", isOn: $viewModel.bedtimeReminderEnabled)
                        .disabled(viewModel.notificationStatus != .authorized)
                    Toggle("Weekly Summary", isOn: $viewModel.weeklySummaryReminderEnabled)
                        .disabled(viewModel.notificationStatus != .authorized)
                }
                .listRowBackground(SQColor.surface)
                .onChange(of: viewModel.bedtimeReminderEnabled) { _, newValue in
                    Task { await viewModel.setBedtimeReminderEnabled(newValue) }
                }
                .onChange(of: viewModel.weeklySummaryReminderEnabled) { _, newValue in
                    Task { await viewModel.setWeeklySummaryReminderEnabled(newValue) }
                }

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
            .task { await viewModel.load() }
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
