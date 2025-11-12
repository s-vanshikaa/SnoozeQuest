//
//  SettingsViewModelTests.swift
//  SnoozeQuestTests
//

import Foundation
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

    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SettingsViewModelTests-\(UUID().uuidString)")!
    }

    @Test func loadFetchesNotificationStatusFromService() async {
        let viewModel = SettingsViewModel(
            notificationService: FakeNotificationService(status: .authorized),
            userDefaults: Self.makeDefaults()
        )

        await viewModel.load()

        #expect(viewModel.notificationStatus == .authorized)
        #expect(viewModel.notificationStatusText == "Enabled")
    }

    @Test func requestNotificationAuthorizationUpdatesStatusFromService() async {
        let viewModel = SettingsViewModel(
            notificationService: FakeNotificationService(status: .notDetermined, statusAfterRequest: .denied),
            userDefaults: Self.makeDefaults()
        )

        await viewModel.requestNotificationAuthorization()

        #expect(viewModel.notificationStatus == .denied)
    }

    @Test func enablingBedtimeReminderSchedulesItUsingTheCurrentGoalBedtime() async {
        let notificationService = FakeNotificationService()
        let goal = SleepGoal(targetDuration: 8 * 3600, bedtime: TimeOfDay(hour: 23, minute: 0), wakeTime: TimeOfDay(hour: 7, minute: 0))
        let viewModel = SettingsViewModel(
            notificationService: notificationService,
            goalRepository: FakeGoalRepository(goal: goal),
            userDefaults: Self.makeDefaults()
        )

        await viewModel.setBedtimeReminderEnabled(true)

        #expect(notificationService.scheduledBedtimes == [TimeOfDay(hour: 23, minute: 0)])
    }

    @Test func disablingBedtimeReminderCancelsIt() async {
        let notificationService = FakeNotificationService()
        let viewModel = SettingsViewModel(notificationService: notificationService, userDefaults: Self.makeDefaults())

        await viewModel.setBedtimeReminderEnabled(false)

        #expect(notificationService.bedtimeReminderCancelled)
    }

    @Test func togglingWeeklySummaryReminderSchedulesAndCancelsIt() async {
        let notificationService = FakeNotificationService()
        let viewModel = SettingsViewModel(notificationService: notificationService, userDefaults: Self.makeDefaults())

        await viewModel.setWeeklySummaryReminderEnabled(true)
        #expect(notificationService.weeklySummarySchedCount == 1)

        await viewModel.setWeeklySummaryReminderEnabled(false)
        #expect(notificationService.weeklySummaryReminderCancelled)
    }

    @Test func preferencesPersistAcrossViewModelInstancesViaUserDefaults() async {
        let defaults = Self.makeDefaults()
        let first = SettingsViewModel(notificationService: FakeNotificationService(), userDefaults: defaults)
        await first.setBedtimeReminderEnabled(true)

        let second = SettingsViewModel(notificationService: FakeNotificationService(), userDefaults: defaults)

        #expect(second.bedtimeReminderEnabled)
    }
}
