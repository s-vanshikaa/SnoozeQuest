//
//  SettingsViewModelTests.swift
//  SnoozeQuestTests
//

import Testing
@testable import SnoozeQuest

@MainActor
struct SettingsViewModelTests {
    @Test func initialStatusReflectsServiceStatus() {
        let viewModel = SettingsViewModel(
            healthKitService: FakeHealthKitService(authorizationStatus: .authorized, statusAfterRequest: .authorized)
        )

        #expect(viewModel.healthKitStatus == .authorized)
        #expect(viewModel.healthKitStatusText == "Connected")
    }

    @Test func connectAppleHealthUpdatesStatusFromService() async {
        let viewModel = SettingsViewModel(
            healthKitService: FakeHealthKitService(authorizationStatus: .notDetermined, statusAfterRequest: .denied)
        )

        await viewModel.connectAppleHealth()

        #expect(viewModel.healthKitStatus == .denied)
        #expect(viewModel.healthKitStatusText == "Access Denied")
    }
}
