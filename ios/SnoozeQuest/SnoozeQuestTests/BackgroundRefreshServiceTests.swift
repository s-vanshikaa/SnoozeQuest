//
//  BackgroundRefreshServiceTests.swift
//  SnoozeQuestTests
//

import Testing
@testable import SnoozeQuest

private struct TestError: Error {}

struct BackgroundRefreshServiceTests {
    @Test func performRefreshReturnsTrueOnSuccessfulImportAndSync() async throws {
        let store = try makeInMemoryStore()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(authorizationStatus: .authorized, statusAfterRequest: .authorized),
            sleepSessionStore: store
        )
        let engine = SyncEngine(apiClient: FakeAPIClient(), sleepSessionStore: store, userID: 1)

        let result = await BackgroundRefreshService.performRefresh(healthKitImportService: importer, syncEngine: engine)

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

        let result = await BackgroundRefreshService.performRefresh(healthKitImportService: importer, syncEngine: engine)

        #expect(result == false)
    }

    @Test func performRefreshReportsFailureWhenCancelledEvenIfWorkCompletes() async throws {
        let store = try makeInMemoryStore()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(authorizationStatus: .authorized, statusAfterRequest: .authorized),
            sleepSessionStore: store
        )
        let engine = SyncEngine(apiClient: FakeAPIClient(), sleepSessionStore: store, userID: 1)

        // Models the expirationHandler firing before the underlying work finishes.
        let task = Task<Bool, Never> {
            await BackgroundRefreshService.performRefresh(healthKitImportService: importer, syncEngine: engine)
        }
        task.cancel()
        let result = await task.value

        #expect(result == false)
    }
}
