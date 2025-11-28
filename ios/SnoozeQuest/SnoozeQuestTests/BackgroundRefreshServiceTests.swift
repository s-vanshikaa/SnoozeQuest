//
//  BackgroundRefreshServiceTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

private struct TestError: Error {}

struct BackgroundRefreshServiceTests {
    private func makeCoordinator(importer: HealthKitImportService, engine: SyncEngine) -> SleepSyncCoordinator {
        SleepSyncCoordinator(
            healthKitImportService: importer, syncEngine: engine,
            userDefaults: UserDefaults(suiteName: "BackgroundRefreshServiceTests-\(UUID().uuidString)")!
        )
    }

    @Test func performRefreshReturnsTrueOnSuccessfulImportAndSync() async throws {
        let store = try makeInMemoryStore()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(authorizationStatus: .authorized, statusAfterRequest: .authorized),
            sleepSessionStore: store
        )
        let engine = SyncEngine(apiClient: FakeAPIClient(), sleepSessionStore: store, userID: 1)
        let coordinator = makeCoordinator(importer: importer, engine: engine)

        let result = await BackgroundRefreshService.performRefresh(coordinator: coordinator)

        #expect(result == true)
    }

    @Test func performRefreshReturnsFalseWhenHealthKitFetchFails() async throws {
        let store = try makeInMemoryStore()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(
                authorizationStatus: .authorized, statusAfterRequest: .authorized, errorToThrow: TestError()
            ),
            sleepSessionStore: store
        )
        let engine = SyncEngine(apiClient: FakeAPIClient(), sleepSessionStore: store, userID: 1)
        let coordinator = makeCoordinator(importer: importer, engine: engine)

        let result = await BackgroundRefreshService.performRefresh(coordinator: coordinator)

        #expect(result == false)
    }

    @Test func performRefreshReportsFailureWhenCancelledEvenIfWorkCompletes() async throws {
        let store = try makeInMemoryStore()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(authorizationStatus: .authorized, statusAfterRequest: .authorized),
            sleepSessionStore: store
        )
        let engine = SyncEngine(apiClient: FakeAPIClient(), sleepSessionStore: store, userID: 1)
        let coordinator = makeCoordinator(importer: importer, engine: engine)

        // Models the expirationHandler firing before the underlying work finishes.
        let task = Task<Bool, Never> {
            await BackgroundRefreshService.performRefresh(coordinator: coordinator)
        }
        task.cancel()
        let result = await task.value

        #expect(result == false)
    }
}
