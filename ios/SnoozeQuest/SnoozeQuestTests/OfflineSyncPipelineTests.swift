//
//  OfflineSyncPipelineTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

// Exercises the full offline pipeline from the PRD's Ticket 21 diagram —
// HealthKit -> SwiftData -> Pending Queue -> SyncEngine -> FastAPI — using fakes for
// HealthKit and the backend, and a real (in-memory) SwiftData store in between.
struct OfflineSyncPipelineTests {
    @Test func aNightImportedFromHealthKitEndsUpSyncedToTheBackend() async throws {
        let start = utcDate(2026, 1, 1, 23, 0)
        let session = SleepSession(
            id: UUID(), startDate: start, endDate: start.addingTimeInterval(8 * 3600),
            stageDurations: [.deep: 5400, .rem: 3600, .core: 18000, .awake: 300]
        )
        let store = try makeInMemoryStore()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(
                authorizationStatus: .authorized, statusAfterRequest: .authorized, sessionsToReturn: [session]
            ),
            sleepSessionStore: store
        )
        let apiClient = FakeAPIClient()
        apiClient.stub(path: "/api/v1/sleep/sync", value: SleepSyncResponseDTO(synced: 1, sessions: []))
        let syncEngine = SyncEngine(apiClient: apiClient, sleepSessionStore: store, userID: 1)

        try await importer.importRecentSleep(days: 7)
        #expect(try store.fetchAll()[0].syncState == .pending)

        try await syncEngine.sync()

        let records = try store.fetchAll()
        #expect(records.count == 1)
        #expect(records[0].syncState == .synced)
        #expect(records[0].deepMinutes == 90)
    }

    @Test func aBackendFailureDuringSyncLeavesTheImportedNightRetryableWithoutReimporting() async throws {
        let start = utcDate(2026, 1, 1, 23, 0)
        let session = SleepSession(
            id: UUID(), startDate: start, endDate: start.addingTimeInterval(8 * 3600),
            stageDurations: [.core: 28800]
        )
        let store = try makeInMemoryStore()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(
                authorizationStatus: .authorized, statusAfterRequest: .authorized, sessionsToReturn: [session]
            ),
            sleepSessionStore: store
        )
        let apiClient = FakeAPIClient()
        apiClient.errorToThrow = APIError.serverError(statusCode: 500)
        let syncEngine = SyncEngine(apiClient: apiClient, sleepSessionStore: store, userID: 1)

        try await importer.importRecentSleep(days: 7)
        try await syncEngine.sync()
        #expect(try store.fetchAll()[0].syncState == .failed)

        // HealthKit re-imports the same night on the next app launch; sync is retried.
        apiClient.errorToThrow = nil
        apiClient.stub(path: "/api/v1/sleep/sync", value: SleepSyncResponseDTO(synced: 1, sessions: []))
        try await importer.importRecentSleep(days: 7)
        try await syncEngine.sync()

        let records = try store.fetchAll()
        #expect(records.count == 1)
        #expect(records[0].syncState == .synced)
    }
}
