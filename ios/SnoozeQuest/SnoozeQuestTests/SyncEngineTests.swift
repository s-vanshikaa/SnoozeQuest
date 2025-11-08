//
//  SyncEngineTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

struct SyncEngineTests {
    private static func seedPendingRecord(in store: SwiftDataSleepSessionStore, externalID: String) throws {
        let start = utcDate(2026, 1, 1, 23, 0)
        try store.save(
            externalID: externalID, startDate: start, endDate: start.addingTimeInterval(8 * 3600),
            deepMinutes: 90, remMinutes: 60, coreMinutes: 300, awakeMinutes: 5
        )
    }

    @Test func successfulUploadMarksTheRecordSynced() async throws {
        let store = try makeInMemoryStore()
        try Self.seedPendingRecord(in: store, externalID: "healthkit-1")
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/sleep/sync", value: SleepSyncResponseDTO(synced: 1, sessions: []))
        let engine = SyncEngine(apiClient: client, sleepSessionStore: store, userID: 1)

        try await engine.sync()

        #expect(try store.fetchAll()[0].syncState == .synced)
        #expect(try store.fetchUnsynced().isEmpty)
    }

    @Test func failedUploadMarksTheRecordFailedAndKeepsItRetryable() async throws {
        let store = try makeInMemoryStore()
        try Self.seedPendingRecord(in: store, externalID: "healthkit-1")
        let client = FakeAPIClient()
        client.errorToThrow = APIError.timeout
        let engine = SyncEngine(apiClient: client, sleepSessionStore: store, userID: 1)

        try await engine.sync()

        #expect(try store.fetchAll()[0].syncState == .failed)
        #expect(try store.fetchUnsynced().count == 1)
    }

    @Test func partialFailureLeavesOnlyTheFailingRecordRetryable() async throws {
        let store = try makeInMemoryStore()
        try Self.seedPendingRecord(in: store, externalID: "healthkit-ok")
        try Self.seedPendingRecord(in: store, externalID: "healthkit-bad")
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/sleep/sync", value: SleepSyncResponseDTO(synced: 1, sessions: []))
        client.queueError(nil)
        client.queueError(APIError.serverError(statusCode: 500))
        let engine = SyncEngine(apiClient: client, sleepSessionStore: store, userID: 1)

        try await engine.sync()

        let unsynced = try store.fetchUnsynced()
        #expect(unsynced.count == 1)
        #expect(unsynced[0].externalID == "healthkit-bad")
    }

    @Test func repeatedSyncOfAnAlreadySyncedRecordDoesNotReuploadIt() async throws {
        let store = try makeInMemoryStore()
        try Self.seedPendingRecord(in: store, externalID: "healthkit-1")
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/sleep/sync", value: SleepSyncResponseDTO(synced: 1, sessions: []))
        let engine = SyncEngine(apiClient: client, sleepSessionStore: store, userID: 1)

        try await engine.sync()
        try await engine.sync()

        #expect(client.requestedEndpoints.count == 1)
    }

    @Test func backendFailureMarksTheRecordFailedAndKeepsItRetryable() async throws {
        let store = try makeInMemoryStore()
        try Self.seedPendingRecord(in: store, externalID: "healthkit-1")
        let client = FakeAPIClient()
        client.errorToThrow = APIError.serverError(statusCode: 500)
        let engine = SyncEngine(apiClient: client, sleepSessionStore: store, userID: 1)

        try await engine.sync()

        #expect(try store.fetchAll()[0].syncState == .failed)
        #expect(try store.fetchUnsynced().count == 1)
    }

    @Test func syncWithNoUnsyncedRecordsMakesNoRequestsAndDoesNotThrow() async throws {
        let store = try makeInMemoryStore()
        let client = FakeAPIClient()
        let engine = SyncEngine(apiClient: client, sleepSessionStore: store, userID: 1)

        try await engine.sync()

        #expect(client.requestedEndpoints.isEmpty)
    }

    @Test func aFailedRecordSucceedsOnTheNextSyncAttempt() async throws {
        let store = try makeInMemoryStore()
        try Self.seedPendingRecord(in: store, externalID: "healthkit-1")
        let client = FakeAPIClient()
        client.errorToThrow = APIError.timeout
        let engine = SyncEngine(apiClient: client, sleepSessionStore: store, userID: 1)

        try await engine.sync()
        #expect(try store.fetchAll()[0].syncState == .failed)

        client.errorToThrow = nil
        client.stub(path: "/api/v1/sleep/sync", value: SleepSyncResponseDTO(synced: 1, sessions: []))
        try await engine.sync()

        #expect(try store.fetchAll()[0].syncState == .synced)
        #expect(client.requestedEndpoints.count == 2)
    }

    @Test func aRecordSavedTwiceLocallyStillSyncsAsOneRecordNotTwo() async throws {
        // Mirrors HealthKit re-importing the same night twice before it's synced — Ticket 18's
        // upsert-by-external-id already collapses this to one local record; this confirms sync
        // then uploads and marks exactly that one record, not two.
        let store = try makeInMemoryStore()
        try Self.seedPendingRecord(in: store, externalID: "healthkit-1")
        try Self.seedPendingRecord(in: store, externalID: "healthkit-1")
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/sleep/sync", value: SleepSyncResponseDTO(synced: 1, sessions: []))
        let engine = SyncEngine(apiClient: client, sleepSessionStore: store, userID: 1)

        try await engine.sync()

        #expect(try store.fetchAll().count == 1)
        #expect(try store.fetchAll()[0].syncState == .synced)
        #expect(client.requestedEndpoints.count == 1)
    }
}
