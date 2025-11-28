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

    // MARK: - Sync

    private static func makeSyncHarness(
        sessions: [SleepSession] = [], apiError: Error? = nil
    ) throws -> (coordinator: SleepSyncCoordinator, store: SwiftDataSleepSessionStore, client: FakeAPIClient, defaults: UserDefaults) {
        let store = try makeInMemoryStore()
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/sleep/sync", value: SleepSyncResponseDTO(synced: 1, sessions: []))
        client.errorToThrow = apiError
        let defaults = makeDefaults()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(
                authorizationStatus: .authorized, statusAfterRequest: .authorized, sessionsToReturn: sessions
            ),
            sleepSessionStore: store
        )
        let coordinator = SleepSyncCoordinator(
            healthKitImportService: importer,
            syncEngine: SyncEngine(apiClient: client, sleepSessionStore: store, userID: 1),
            userDefaults: defaults
        )
        return (coordinator, store, client, defaults)
    }

    private static func makeNight() -> SleepSession {
        let start = utcDate(2026, 2, 1, 23, 0)
        return SleepSession(
            id: UUID(), startDate: start, endDate: start.addingTimeInterval(8 * 3600), stageDurations: [.core: 28800]
        )
    }

    @Test func connectingAppleHealthImmediatelyImportsAndUploadsSleep() async throws {
        let harness = try Self.makeSyncHarness(sessions: [Self.makeNight()])
        let viewModel = SettingsViewModel(
            healthKitService: FakeHealthKitService(authorizationStatus: .notDetermined, statusAfterRequest: .authorized),
            syncCoordinator: harness.coordinator,
            userDefaults: harness.defaults
        )
        #expect(viewModel.lastSyncText == "Never")

        await viewModel.connectAppleHealth()

        #expect(viewModel.healthKitStatus == .authorized)
        #expect(try harness.store.fetchAll().count == 1)
        #expect(try harness.store.fetchUnsynced().isEmpty)
        #expect(viewModel.lastSyncDate != nil)
        #expect(viewModel.lastSyncText != "Never")
    }

    @Test func deniedAppleHealthAccessDoesNotAttemptAnImport() async throws {
        let harness = try Self.makeSyncHarness(sessions: [Self.makeNight()])
        let viewModel = SettingsViewModel(
            healthKitService: FakeHealthKitService(authorizationStatus: .notDetermined, statusAfterRequest: .denied),
            syncCoordinator: harness.coordinator,
            userDefaults: harness.defaults
        )

        await viewModel.connectAppleHealth()

        #expect(try harness.store.fetchAll().isEmpty)
        #expect(viewModel.lastSyncDate == nil)
    }

    @Test func syncNowRetriesRecordsThatFailedEarlierAndUpdatesLastSync() async throws {
        let harness = try Self.makeSyncHarness(sessions: [Self.makeNight()], apiError: APIError.timeout)
        let viewModel = SettingsViewModel(
            healthKitService: FakeHealthKitService(authorizationStatus: .authorized, statusAfterRequest: .authorized),
            syncCoordinator: harness.coordinator,
            userDefaults: harness.defaults
        )

        await viewModel.syncNow()
        #expect(viewModel.lastSyncOutcome == .syncFailed)
        #expect(viewModel.syncStatusMessage != nil)
        #expect(viewModel.lastSyncDate == nil)

        harness.client.errorToThrow = nil
        await viewModel.syncNow()

        #expect(viewModel.lastSyncOutcome == .synced)
        #expect(viewModel.syncStatusMessage == nil)
        #expect(viewModel.lastSyncDate != nil)
        #expect(try harness.store.fetchUnsynced().isEmpty)
    }

    @Test func syncNowIsOnlyAvailableWhenAppleHealthIsConnected() throws {
        let harness = try Self.makeSyncHarness()
        let connected = SettingsViewModel(
            healthKitService: FakeHealthKitService(authorizationStatus: .authorized, statusAfterRequest: .authorized),
            syncCoordinator: harness.coordinator, userDefaults: harness.defaults
        )
        let notConnected = SettingsViewModel(
            healthKitService: FakeHealthKitService(authorizationStatus: .notDetermined, statusAfterRequest: .authorized),
            syncCoordinator: harness.coordinator, userDefaults: harness.defaults
        )

        #expect(connected.canSyncNow)
        #expect(!notConnected.canSyncNow)
    }

    @Test func lastSyncTimeIsRestoredWhenTheViewModelIsRecreated() async throws {
        let harness = try Self.makeSyncHarness()
        let first = SettingsViewModel(
            healthKitService: FakeHealthKitService(authorizationStatus: .authorized, statusAfterRequest: .authorized),
            syncCoordinator: harness.coordinator, userDefaults: harness.defaults
        )
        await first.syncNow()

        let second = SettingsViewModel(
            healthKitService: FakeHealthKitService(authorizationStatus: .authorized, statusAfterRequest: .authorized),
            syncCoordinator: harness.coordinator, userDefaults: harness.defaults
        )

        #expect(second.lastSyncDate == first.lastSyncDate)
        #expect(second.lastSyncDate != nil)
    }
}
