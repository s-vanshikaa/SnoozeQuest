//
//  SyncEngine.swift
//  SnoozeQuest
//

import Foundation

struct SyncSummary: Equatable {
    let synced: Int
    let failed: Int
}

final class SyncEngine {
    private let apiClient: APIClientProtocol
    private let sleepSessionStore: SleepSessionStore
    private let userID: Int

    init(apiClient: APIClientProtocol, sleepSessionStore: SleepSessionStore, userID: Int) {
        self.apiClient = apiClient
        self.sleepSessionStore = sleepSessionStore
        self.userID = userID
    }

    @discardableResult
    func sync() async throws -> SyncSummary {
        let pending = try sleepSessionStore.fetchUnsynced()
        var synced = 0
        for record in pending {
            if await upload(record) {
                synced += 1
            }
        }
        return SyncSummary(synced: synced, failed: pending.count - synced)
    }

    /// Returns whether the backend accepted the record.
    private func upload(_ record: SleepSessionRecord) async -> Bool {
        let payload = SleepSyncRequestDTO(
            userId: userID,
            sessions: [SleepSessionUploadDTO(
                externalId: record.externalID,
                startTime: record.startDate,
                endTime: record.endDate,
                deepMinutes: record.deepMinutes,
                remMinutes: record.remMinutes,
                coreMinutes: record.coreMinutes,
                awakeMinutes: record.awakeMinutes
            )]
        )

        let newState: SyncState
        do {
            let body = try APIClient.makeEncoder().encode(payload)
            let endpoint = Endpoint(path: "/api/v1/sleep/sync", method: .post, body: body)
            let _: SleepSyncResponseDTO = try await apiClient.request(endpoint)
            newState = .synced
        } catch {
            newState = .failed
        }

        // If this local write fails, the record stays pending and gets retried next sync —
        // safe because the backend upserts by external_id, so re-uploading is a no-op.
        try? sleepSessionStore.updateSyncState(externalID: record.externalID, to: newState)
        return newState == .synced
    }
}
