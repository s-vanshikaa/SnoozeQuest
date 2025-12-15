//
//  SleepSyncCoordinatorTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

private struct TestError: Error {}

struct SleepSyncCoordinatorTests {
    private struct Harness {
        let coordinator: SleepSyncCoordinator
        let store: SwiftDataSleepSessionStore
        let apiClient: FakeAPIClient
        let userDefaults: UserDefaults
        let notificationCenter: NotificationCenter
    }

    private static let syncedAt = utcDate(2026, 3, 1, 12, 0)

    private static func makeSession(night: Int) -> SleepSession {
        let start = utcDate(2026, 2, night, 23, 0)
        return SleepSession(
            id: UUID(), startDate: start, endDate: start.addingTimeInterval(8 * 3600),
            stageDurations: [.deep: 5400, .rem: 3600, .core: 18000, .awake: 300]
        )
    }

    private static func makeHarness(
        sessions: [SleepSession] = [],
        healthKitError: Error? = nil,
        apiError: Error? = nil
    ) throws -> Harness {
        let store = try makeInMemoryStore()
        let apiClient = FakeAPIClient()
        apiClient.stub(path: "/api/v1/sleep/sync", value: SleepSyncResponseDTO(synced: 1, sessions: []))
        apiClient.errorToThrow = apiError
        let userDefaults = UserDefaults(suiteName: "SleepSyncCoordinatorTests-\(UUID().uuidString)")!
        let notificationCenter = NotificationCenter()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(
                authorizationStatus: .authorized, statusAfterRequest: .authorized,
                sessionsToReturn: sessions, errorToThrow: healthKitError
            ),
            sleepSessionStore: store
        )
        let coordinator = SleepSyncCoordinator(
            healthKitImportService: importer,
            syncEngine: SyncEngine(apiClient: apiClient, sleepSessionStore: store, userID: 1, sleep: { _ in }),
            userDefaults: userDefaults,
            notificationCenter: notificationCenter,
            now: { syncedAt }
        )
        return Harness(
            coordinator: coordinator, store: store, apiClient: apiClient,
            userDefaults: userDefaults, notificationCenter: notificationCenter
        )
    }

    @Test func successfulImportPersistsSessionsUploadsThemAndRecordsTheSyncTime() async throws {
        let harness = try Self.makeHarness(sessions: [Self.makeSession(night: 1), Self.makeSession(night: 2)])

        let outcome = await harness.coordinator.refresh()

        #expect(outcome == .synced)
        let records = try harness.store.fetchAll()
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.syncState == .synced })
        #expect(harness.apiClient.requestedEndpoints.count == 1) // both nights go up in one batch
        #expect(harness.coordinator.lastSuccessfulSync == Self.syncedAt)
    }

    @Test func lastSyncTimeSurvivesANewCoordinatorInstance() async throws {
        let harness = try Self.makeHarness(sessions: [Self.makeSession(night: 1)])
        _ = await harness.coordinator.refresh()

        let reloaded = SleepSyncCoordinator(
            healthKitImportService: HealthKitImportService(
                healthKitService: FakeHealthKitService(authorizationStatus: .authorized, statusAfterRequest: .authorized),
                sleepSessionStore: harness.store
            ),
            syncEngine: SyncEngine(apiClient: harness.apiClient, sleepSessionStore: harness.store, userID: 1, sleep: { _ in }),
            userDefaults: harness.userDefaults
        )

        #expect(reloaded.lastSuccessfulSync == Self.syncedAt)
    }

    @Test func emptyHealthKitResultIsASuccessfulSyncThatUploadsNothing() async throws {
        let harness = try Self.makeHarness(sessions: [])

        let outcome = await harness.coordinator.refresh()

        #expect(outcome == .synced)
        #expect(try harness.store.fetchAll().isEmpty)
        #expect(harness.apiClient.requestedEndpoints.isEmpty)
        #expect(harness.coordinator.lastSuccessfulSync == Self.syncedAt)
    }

    @Test func failedImportReportsFailureWithoutUploadingOrUpdatingTheSyncTime() async throws {
        let harness = try Self.makeHarness(sessions: [Self.makeSession(night: 1)], healthKitError: TestError())

        let outcome = await harness.coordinator.refresh()

        #expect(outcome == .importFailed)
        #expect(try harness.store.fetchAll().isEmpty)
        #expect(harness.apiClient.requestedEndpoints.isEmpty)
        #expect(harness.coordinator.lastSuccessfulSync == nil)
    }

    @Test func failedUploadKeepsImportedRecordsPendingAndDoesNotUpdateTheSyncTime() async throws {
        let harness = try Self.makeHarness(sessions: [Self.makeSession(night: 1)], apiError: APIError.timeout)

        let outcome = await harness.coordinator.refresh()

        #expect(outcome == .syncFailed)
        #expect(try harness.store.fetchAll().count == 1)
        #expect(try harness.store.fetchUnsynced().count == 1)
        #expect(harness.coordinator.lastSuccessfulSync == nil)
    }

    @Test func aLaterRefreshUploadsRecordsThatFailedEarlier() async throws {
        let harness = try Self.makeHarness(sessions: [Self.makeSession(night: 1)], apiError: APIError.timeout)
        _ = await harness.coordinator.refresh()

        harness.apiClient.errorToThrow = nil
        let outcome = await harness.coordinator.refresh()

        #expect(outcome == .synced)
        #expect(try harness.store.fetchUnsynced().isEmpty)
        #expect(try harness.store.fetchAll().count == 1)
        #expect(harness.coordinator.lastSuccessfulSync == Self.syncedAt)
    }

    @Test func refreshNotifiesSoScreensCanReload() async throws {
        let harness = try Self.makeHarness(sessions: [Self.makeSession(night: 1)])
        var notificationCount = 0
        let observer = harness.notificationCenter.addObserver(
            forName: .sleepDataDidSync, object: nil, queue: nil
        ) { _ in notificationCount += 1 }
        defer { harness.notificationCenter.removeObserver(observer) }

        _ = await harness.coordinator.refresh()

        #expect(notificationCount == 1)
    }

    @Test func overlappingRefreshesShareOneRun() async throws {
        let harness = try Self.makeHarness(sessions: [Self.makeSession(night: 1)])

        async let first = harness.coordinator.refresh()
        async let second = harness.coordinator.refresh()
        let outcomes = await [first, second]

        #expect(outcomes == [.synced, .synced])
        #expect(harness.apiClient.requestedEndpoints.count == 1)
    }
}
