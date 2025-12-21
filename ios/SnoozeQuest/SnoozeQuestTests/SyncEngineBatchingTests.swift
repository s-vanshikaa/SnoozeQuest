//
//  SyncEngineBatchingTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

/// An in-memory stand-in for the backend that behaves like the real upsert: it keeps one
/// entry per external_id, so a request that is delivered twice can't create a duplicate.
final class FakeSyncServer: APIClientProtocol {
    enum Behavior {
        case accept
        case fail(Error)
        /// The server commits the batch, but the response never reaches the client.
        case acceptThenDropResponse(Error)
    }

    private(set) var storedExternalIDs: Set<String> = []
    private(set) var requestBatchSizes: [Int] = []
    private(set) var acceptedRequestCount = 0
    /// Consumed one per request; once empty, requests are accepted.
    var script: [Behavior] = []
    /// A batch containing any of these is rejected outright, like a validation failure.
    var rejectedExternalIDs: Set<String> = []

    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let externalIDs = try Self.externalIDs(in: endpoint)
        requestBatchSizes.append(externalIDs.count)

        if !rejectedExternalIDs.isDisjoint(with: externalIDs) {
            throw APIError.validationError(message: "invalid session")
        }

        switch script.isEmpty ? .accept : script.removeFirst() {
        case .fail(let error):
            throw error
        case .acceptThenDropResponse(let error):
            commit(externalIDs)
            throw error
        case .accept:
            commit(externalIDs)
        }

        let response = SleepSyncResponseDTO(synced: externalIDs.count, sessions: [])
        guard let typed = response as? T else { fatalError("FakeSyncServer only serves the sync response") }
        return typed
    }

    private func commit(_ externalIDs: [String]) {
        acceptedRequestCount += 1
        storedExternalIDs.formUnion(externalIDs)
    }

    private static func externalIDs(in endpoint: Endpoint) throws -> [String] {
        let body = try #require(endpoint.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sessions = try #require(json["sessions"] as? [[String: Any]])
        return sessions.compactMap { $0["external_id"] as? String }
    }
}

private final class SleepRecorder {
    private(set) var delays: [TimeInterval] = []
    func record(_ delay: TimeInterval) { delays.append(delay) }
}

struct SyncEngineBatchingTests {
    private struct Harness {
        let engine: SyncEngine
        let store: SwiftDataSleepSessionStore
        let server: FakeSyncServer
        let sleeps: SleepRecorder
    }

    private static func makeHarness(recordCount: Int, randomUnit: Double = 1) throws -> Harness {
        let store = try makeInMemoryStore()
        let start = utcDate(2026, 1, 1, 23, 0)
        for index in 0..<recordCount {
            try store.save(
                externalID: "session-\(String(format: "%04d", index))",
                startDate: start.addingTimeInterval(TimeInterval(index) * 86400),
                endDate: start.addingTimeInterval(TimeInterval(index) * 86400 + 8 * 3600),
                deepMinutes: 90, remMinutes: 60, coreMinutes: 300, awakeMinutes: 5
            )
        }
        let server = FakeSyncServer()
        let sleeps = SleepRecorder()
        let engine = SyncEngine(
            apiClient: server, sleepSessionStore: store, userID: 1,
            sleep: { sleeps.record($0) }, randomUnit: { randomUnit }
        )
        return Harness(engine: engine, store: store, server: server, sleeps: sleeps)
    }

    // MARK: - Batching

    @Test func zeroRecordsMakeNoRequests() async throws {
        let harness = try Self.makeHarness(recordCount: 0)

        let summary = try await harness.engine.sync()

        #expect(summary == SyncSummary(synced: 0, failed: 0))
        #expect(harness.server.requestBatchSizes.isEmpty)
    }

    @Test func oneRecordIsSentInOneRequest() async throws {
        let harness = try Self.makeHarness(recordCount: 1)

        let summary = try await harness.engine.sync()

        #expect(summary == SyncSummary(synced: 1, failed: 0))
        #expect(harness.server.requestBatchSizes == [1])
    }

    @Test func exactlyOneHundredRecordsFitInASingleRequest() async throws {
        let harness = try Self.makeHarness(recordCount: 100)

        let summary = try await harness.engine.sync()

        #expect(SyncEngine.batchSize == 100)
        #expect(summary == SyncSummary(synced: 100, failed: 0))
        #expect(harness.server.requestBatchSizes == [100])
        #expect(try harness.store.fetchUnsynced().isEmpty)
    }

    @Test func oneHundredAndOneRecordsSplitIntoTwoRequests() async throws {
        let harness = try Self.makeHarness(recordCount: 101)

        let summary = try await harness.engine.sync()

        #expect(summary == SyncSummary(synced: 101, failed: 0))
        #expect(harness.server.requestBatchSizes == [100, 1])
    }

    @Test func manyRecordsAreSentInBatchesOfAtMostOneHundred() async throws {
        let harness = try Self.makeHarness(recordCount: 250)

        try await harness.engine.sync()

        #expect(harness.server.requestBatchSizes == [100, 100, 50])
        #expect(harness.server.storedExternalIDs.count == 250)
        #expect(try harness.store.fetchUnsynced().isEmpty)
    }

    // MARK: - Transient failures

    @Test func aTransientFailureFollowedBySuccessSyncsTheBatchAfterOneBackoff() async throws {
        let harness = try Self.makeHarness(recordCount: 3)
        harness.server.script = [.fail(APIError.timeout), .accept]

        let summary = try await harness.engine.sync()

        #expect(summary == SyncSummary(synced: 3, failed: 0))
        #expect(harness.server.requestBatchSizes == [3, 3])
        #expect(harness.sleeps.delays.count == 1)
        #expect(try harness.store.fetchUnsynced().isEmpty)
    }

    @Test(arguments: [
        APIError.timeout, APIError.connectionFailed, APIError.rateLimited,
        APIError.serverError(statusCode: 500), APIError.serverError(statusCode: 503),
    ])
    func everyTransientErrorIsRetried(error: APIError) async throws {
        let harness = try Self.makeHarness(recordCount: 1)
        harness.server.script = [.fail(error), .accept]

        try await harness.engine.sync()

        #expect(harness.server.requestBatchSizes == [1, 1])
        #expect(try harness.store.fetchUnsynced().isEmpty)
    }

    @Test func retriesAreBoundedAndTheBatchIsLeftRetryable() async throws {
        let harness = try Self.makeHarness(recordCount: 2)
        harness.server.script = Array(repeating: .fail(APIError.connectionFailed), count: 50)

        let summary = try await harness.engine.sync()

        let attempts = RetryPolicy.default.maxAttempts
        #expect(harness.server.requestBatchSizes.count == attempts)
        #expect(harness.sleeps.delays.count == attempts - 1)
        #expect(summary == SyncSummary(synced: 0, failed: 2))
        #expect(try harness.store.fetchUnsynced().count == 2)
        #expect(try harness.store.fetchAll().allSatisfy { $0.syncState == .failed })
    }

    // MARK: - Tolerating intermittent failures

    private static var exhaustedBatch: [FakeSyncServer.Behavior] {
        Array(repeating: .fail(APIError.timeout), count: RetryPolicy.default.maxAttempts)
    }

    private static func states(_ harness: Harness) throws -> [SyncState] {
        try harness.store.fetchAll().map(\.syncState)
    }

    @Test func oneExhaustedBatchDoesNotStopTheRestOfTheSync() async throws {
        let harness = try Self.makeHarness(recordCount: 300)
        harness.server.script = Self.exhaustedBatch // batch 1 fails every attempt; the rest succeed

        let summary = try await harness.engine.sync()

        #expect(summary == SyncSummary(synced: 200, failed: 100))
        #expect(harness.server.requestBatchSizes == [100, 100, 100, 100, 100, 100])
        let states = try Self.states(harness)
        #expect(states.prefix(100).allSatisfy { $0 == .failed })
        #expect(states.suffix(200).allSatisfy { $0 == .synced })
    }

    @Test func twoConsecutiveExhaustedBatchesStillAllowTheSyncToContinue() async throws {
        let harness = try Self.makeHarness(recordCount: 300)
        harness.server.script = Self.exhaustedBatch + Self.exhaustedBatch

        let summary = try await harness.engine.sync()

        #expect(summary == SyncSummary(synced: 100, failed: 200))
        let expectedRequests: Int = 4 + 4 + 1
        #expect(harness.server.requestBatchSizes.count == expectedRequests)
        let states = try Self.states(harness)
        #expect(states.suffix(100).allSatisfy { $0 == .synced })
    }

    @Test func threeConsecutiveExhaustedBatchesStopTheSync() async throws {
        #expect(SyncEngine.maxConsecutiveExhaustedBatches == 3)
        let harness = try Self.makeHarness(recordCount: 500)
        harness.server.script = Self.exhaustedBatch + Self.exhaustedBatch + Self.exhaustedBatch

        let summary = try await harness.engine.sync()

        #expect(summary == SyncSummary(synced: 0, failed: 500))
        // Three batches were attempted, four tries each; batches 4 and 5 were never sent.
        let expectedBatchSizes: [Int] = Array(repeating: 100, count: 12)
        #expect(harness.server.requestBatchSizes == expectedBatchSizes)
        let states = try Self.states(harness)
        #expect(states.filter { $0 == .failed }.count == 300)
        #expect(states.filter { $0 == .pending }.count == 200)
        #expect(harness.server.storedExternalIDs.isEmpty)
    }

    @Test func aSuccessfulBatchResetsTheConsecutiveExhaustedCount() async throws {
        let harness = try Self.makeHarness(recordCount: 500)
        // exhausted, exhausted, ok, exhausted, exhausted: four exhausted batches in total, but
        // never three in a row, so every batch is attempted.
        harness.server.script = Self.exhaustedBatch + Self.exhaustedBatch + [.accept]
            + Self.exhaustedBatch + Self.exhaustedBatch

        let summary = try await harness.engine.sync()

        #expect(summary == SyncSummary(synced: 100, failed: 400))
        let expectedRequests: Int = 17 // 4 + 4 + 1 + 4 + 4
        #expect(harness.server.requestBatchSizes.count == expectedRequests)
        let states = try Self.states(harness)
        #expect(states.filter { $0 == .synced }.count == 100)
        #expect(states.filter { $0 == .failed }.count == 400)
        #expect(states.filter { $0 == .pending }.isEmpty)
    }

    @Test func exhaustedBatchesStayRetryableAndUploadOnTheNextSync() async throws {
        let harness = try Self.makeHarness(recordCount: 300)
        harness.server.script = Self.exhaustedBatch

        try await harness.engine.sync()
        #expect(try harness.store.fetchUnsynced().count == 100)

        try await harness.engine.sync()

        #expect(try harness.store.fetchUnsynced().isEmpty)
        #expect(harness.server.storedExternalIDs.count == 300)
    }

    @Test func resendingBatchesTheServerAlreadyAcceptedNeverDuplicates() async throws {
        let harness = try Self.makeHarness(recordCount: 300)
        // Batch 1 is committed on the server four times but every response is lost, so the
        // client believes it failed and sends it again on the next sync.
        harness.server.script = Array(
            repeating: .acceptThenDropResponse(APIError.connectionFailed), count: RetryPolicy.default.maxAttempts
        )

        try await harness.engine.sync()
        #expect(try harness.store.fetchUnsynced().count == 100)
        #expect(harness.server.storedExternalIDs.count == 300)

        try await harness.engine.sync()

        #expect(try harness.store.fetchUnsynced().isEmpty)
        #expect(harness.server.storedExternalIDs.count == 300) // still 300 unique, not 300 + resends
        let expectedAccepted: Int = 7 // batch 1 committed 4x (lost responses), batches 2 and 3 once each, batch 1 resent once
        #expect(harness.server.acceptedRequestCount == expectedAccepted)
    }

    @Test func cancellationStopsTheSyncImmediatelyInsteadOfMovingToTheNextBatch() async throws {
        let store = try makeInMemoryStore()
        let start = utcDate(2026, 1, 1, 23, 0)
        for index in 0..<300 {
            try store.save(
                externalID: "session-\(String(format: "%04d", index))",
                startDate: start.addingTimeInterval(TimeInterval(index) * 86400),
                endDate: start.addingTimeInterval(TimeInterval(index) * 86400 + 8 * 3600),
                deepMinutes: 90, remMinutes: 60, coreMinutes: 300, awakeMinutes: 5
            )
        }
        let server = FakeSyncServer()
        server.script = Array(repeating: .fail(APIError.timeout), count: 50)
        let engine = SyncEngine(
            apiClient: server, sleepSessionStore: store, userID: 1,
            sleep: { _ in throw CancellationError() }
        )

        try await engine.sync()

        #expect(server.requestBatchSizes == [100]) // batches 2 and 3 were never attempted
        let states = try store.fetchAll().map(\.syncState)
        #expect(states.filter { $0 == .pending }.count == 200)
    }

    @Test func backoffDelaysGrowExponentiallyAndStayWithinTheCap() async throws {
        let harness = try Self.makeHarness(recordCount: 1, randomUnit: 1)
        harness.server.script = Array(repeating: .fail(APIError.timeout), count: 50)

        try await harness.engine.sync()

        #expect(harness.sleeps.delays == [0.5, 1, 2])
    }

    @Test func retryPolicyCapsDelaysAndAppliesJitter() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: 0.5, maxDelay: 8)

        #expect(policy.delay(retryIndex: 0, randomUnit: 1) == 0.5)
        #expect(policy.delay(retryIndex: 3, randomUnit: 1) == 4)
        #expect(policy.delay(retryIndex: 4, randomUnit: 1) == 8)
        #expect(policy.delay(retryIndex: 20, randomUnit: 1) == 8)
        #expect(policy.delay(retryIndex: 3, randomUnit: 0.5) == 2)
        #expect(policy.delay(retryIndex: 3, randomUnit: 0) == 0)
    }

    // MARK: - Permanent failures

    @Test func aPermanentFailureIsNotRetried() async throws {
        let harness = try Self.makeHarness(recordCount: 1)
        harness.server.rejectedExternalIDs = ["session-0000"]

        let summary = try await harness.engine.sync()

        #expect(harness.server.requestBatchSizes == [1])
        #expect(harness.sleeps.delays.isEmpty)
        #expect(summary == SyncSummary(synced: 0, failed: 1))
        #expect(try harness.store.fetchAll()[0].syncState == .failed)
    }

    @Test func oneRejectedRecordDoesNotBlockTheGoodRecordsInItsBatch() async throws {
        let harness = try Self.makeHarness(recordCount: 8)
        harness.server.rejectedExternalIDs = ["session-0005"]

        let summary = try await harness.engine.sync()

        #expect(summary == SyncSummary(synced: 7, failed: 1))
        #expect(harness.sleeps.delays.isEmpty)
        let unsynced = try harness.store.fetchUnsynced()
        #expect(unsynced.map(\.externalID) == ["session-0005"])
        #expect(harness.server.storedExternalIDs.count == 7)
    }

    @Test func splittingARejectedBatchUsesFewRequests() async throws {
        let harness = try Self.makeHarness(recordCount: 100)
        harness.server.rejectedExternalIDs = ["session-0042"]

        try await harness.engine.sync()

        // One full batch plus roughly two requests per halving level, not one per record.
        #expect(harness.server.requestBatchSizes.count <= 2 * 7 + 1)
        #expect(try harness.store.fetchUnsynced().count == 1)
    }

    // MARK: - Idempotency

    @Test func syncingTwiceDoesNotUploadOrDuplicateAnything() async throws {
        let harness = try Self.makeHarness(recordCount: 120)

        try await harness.engine.sync()
        let requestsAfterFirstSync = harness.server.requestBatchSizes.count
        try await harness.engine.sync()

        #expect(harness.server.requestBatchSizes.count == requestsAfterFirstSync)
        #expect(harness.server.storedExternalIDs.count == 120)
    }

    @Test func retryingAfterTheServerAlreadyAcceptedTheRequestDoesNotDuplicate() async throws {
        let harness = try Self.makeHarness(recordCount: 100)
        // The first request is committed on the server but its response is lost.
        harness.server.script = [.acceptThenDropResponse(APIError.timeout), .accept]

        let summary = try await harness.engine.sync()

        #expect(summary == SyncSummary(synced: 100, failed: 0))
        #expect(harness.server.requestBatchSizes == [100, 100])
        #expect(harness.server.acceptedRequestCount == 2)
        #expect(harness.server.storedExternalIDs.count == 100)
        #expect(try harness.store.fetchUnsynced().isEmpty)
    }

    @Test func aBatchLostAfterAcceptanceIsResentOnTheNextSyncWithoutDuplicates() async throws {
        let harness = try Self.makeHarness(recordCount: 10)
        harness.server.script = Array(repeating: .acceptThenDropResponse(APIError.connectionFailed), count: 4)

        try await harness.engine.sync()
        #expect(try harness.store.fetchUnsynced().count == 10)

        harness.server.script = []
        try await harness.engine.sync()

        #expect(try harness.store.fetchUnsynced().isEmpty)
        #expect(harness.server.storedExternalIDs.count == 10)
    }
}
