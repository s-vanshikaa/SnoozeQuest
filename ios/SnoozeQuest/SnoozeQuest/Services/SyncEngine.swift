//
//  SyncEngine.swift
//  SnoozeQuest
//

import Foundation

struct SyncSummary: Equatable {
    let synced: Int
    let failed: Int
}

/// Bounded exponential backoff with full jitter: the wait before retry `n` is a random value
/// between 0 and `min(maxDelay, baseDelay * 2^n)`. Jitter keeps many clients that failed at the
/// same moment from all retrying at the same moment.
struct RetryPolicy {
    /// Total tries per request, including the first.
    var maxAttempts = 4
    var baseDelay: TimeInterval = 0.5
    var maxDelay: TimeInterval = 8

    static let `default` = RetryPolicy()

    /// `retryIndex` is 0 for the wait before the first retry. `randomUnit` is in 0...1.
    func delay(retryIndex: Int, randomUnit: Double) -> TimeInterval {
        let exponent = min(retryIndex, 30)
        let ceiling = min(maxDelay, baseDelay * pow(2, Double(exponent)))
        return ceiling * min(max(randomUnit, 0), 1)
    }
}

final class SyncEngine {
    /// Most sessions sent in one request. The backend accepts more; this keeps request bodies
    /// small and limits how much a single failed request puts back in the queue.
    static let batchSize = 100

    /// A sync gives up after this many batches in a row each use up all their retries. One
    /// unlucky batch on a flaky connection shouldn't strand the rest, but a run of them means
    /// the network is really down and trying further batches would only burn time and battery.
    static let maxConsecutiveExhaustedBatches = 3

    private let apiClient: APIClientProtocol
    private let sleepSessionStore: SleepSessionStore
    private let userID: Int
    private let retryPolicy: RetryPolicy
    private let sleep: (TimeInterval) async throws -> Void
    private let randomUnit: () -> Double

    init(
        apiClient: APIClientProtocol,
        sleepSessionStore: SleepSessionStore,
        userID: Int,
        retryPolicy: RetryPolicy = .default,
        sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        randomUnit: @escaping () -> Double = { Double.random(in: 0...1) }
    ) {
        self.apiClient = apiClient
        self.sleepSessionStore = sleepSessionStore
        self.userID = userID
        self.retryPolicy = retryPolicy
        self.sleep = sleep
        self.randomUnit = randomUnit
    }

    /// Uploads everything not yet synced, `batchSize` records per request.
    ///
    /// A batch that still fails after its retries stays unsynced and the sync moves on to the
    /// next one. The sync stops once `maxConsecutiveExhaustedBatches` batches in a row have
    /// done that, or when the task is cancelled; records not reached stay pending for the next
    /// sync.
    @discardableResult
    func sync() async throws -> SyncSummary {
        let pending = try sleepSessionStore.fetchUnsynced()
        var state = RunState()

        var start = 0
        while start < pending.count && !state.shouldStop {
            let end = min(start + Self.batchSize, pending.count)
            await upload(Array(pending[start..<end]), state: &state)
            start = end
        }
        return SyncSummary(synced: state.synced, failed: pending.count - state.synced)
    }

    private struct RunState {
        var synced = 0
        var consecutiveExhaustedBatches = 0
        var wasCancelled = false

        var shouldStop: Bool {
            wasCancelled || consecutiveExhaustedBatches >= SyncEngine.maxConsecutiveExhaustedBatches
        }
    }

    private func upload(_ records: [SleepSessionRecord], state: inout RunState) async {
        // Snapshot before any await so the payload can't change between attempts.
        let uploads = records.map(Self.makeUpload)
        let externalIDs = records.map(\.externalID)

        switch await send(uploads) {
        case .success:
            // If this local write fails the records stay pending and are re-sent next sync —
            // safe because the backend upserts by (user_id, external_id).
            try? sleepSessionStore.updateSyncState(externalIDs: externalIDs, to: .synced)
            state.synced += records.count
            state.consecutiveExhaustedBatches = 0

        case .transientFailure:
            try? sleepSessionStore.updateSyncState(externalIDs: externalIDs, to: .failed)
            state.consecutiveExhaustedBatches += 1

        case .cancelled:
            try? sleepSessionStore.updateSyncState(externalIDs: externalIDs, to: .failed)
            state.wasCancelled = true

        case .permanentFailure:
            // The server answered, so the network is up: this doesn't count toward giving up.
            state.consecutiveExhaustedBatches = 0
            // The backend rejects a batch as a whole, so one bad record would otherwise block
            // the rest for good. Split to isolate it; the good records still go through.
            guard records.count > 1 else {
                try? sleepSessionStore.updateSyncState(externalIDs: externalIDs, to: .failed)
                return
            }
            let middle = records.count / 2
            await upload(Array(records[..<middle]), state: &state)
            if state.shouldStop { return }
            await upload(Array(records[middle...]), state: &state)
        }
    }

    private enum SendOutcome {
        case success
        case transientFailure
        case cancelled
        case permanentFailure
    }

    private func send(_ uploads: [SleepSessionUploadDTO]) async -> SendOutcome {
        let body: Data
        do {
            body = try APIClient.makeEncoder().encode(SleepSyncRequestDTO(userId: userID, sessions: uploads))
        } catch {
            return .permanentFailure
        }
        let endpoint = Endpoint(path: "/api/v1/sleep/sync", method: .post, body: body)

        for attempt in 0..<retryPolicy.maxAttempts {
            do {
                let _: SleepSyncResponseDTO = try await apiClient.request(endpoint)
                return .success
            } catch let error as APIError where error.isTransient {
                let isLastAttempt = attempt == retryPolicy.maxAttempts - 1
                if isLastAttempt { return .transientFailure }
                let delay = retryPolicy.delay(retryIndex: attempt, randomUnit: randomUnit())
                do {
                    try await sleep(delay)
                } catch {
                    return .cancelled // the task was cancelled while waiting to retry
                }
            } catch {
                return .permanentFailure
            }
        }
        return .transientFailure
    }

    private static func makeUpload(_ record: SleepSessionRecord) -> SleepSessionUploadDTO {
        SleepSessionUploadDTO(
            externalId: record.externalID,
            startTime: record.startDate,
            endTime: record.endDate,
            deepMinutes: record.deepMinutes,
            remMinutes: record.remMinutes,
            coreMinutes: record.coreMinutes,
            awakeMinutes: record.awakeMinutes
        )
    }
}
