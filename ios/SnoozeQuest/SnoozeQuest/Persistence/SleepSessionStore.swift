//
//  SleepSessionStore.swift
//  SnoozeQuest
//

import Foundation
import SwiftData

protocol SleepSessionStore {
    func save(
        externalID: String,
        startDate: Date,
        endDate: Date,
        deepMinutes: Int,
        remMinutes: Int,
        coreMinutes: Int,
        awakeMinutes: Int
    ) throws
    func fetchAll() throws -> [SleepSessionRecord]
    func fetchUnsynced() throws -> [SleepSessionRecord]
    func updateSyncState(externalID: String, to state: SyncState) throws
}

final class SwiftDataSleepSessionStore: SleepSessionStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func save(
        externalID: String,
        startDate: Date,
        endDate: Date,
        deepMinutes: Int,
        remMinutes: Int,
        coreMinutes: Int,
        awakeMinutes: Int
    ) throws {
        if let existing = try fetchRecord(externalID: externalID) {
            existing.startDate = startDate
            existing.endDate = endDate
            existing.deepMinutes = deepMinutes
            existing.remMinutes = remMinutes
            existing.coreMinutes = coreMinutes
            existing.awakeMinutes = awakeMinutes
        } else {
            context.insert(SleepSessionRecord(
                externalID: externalID,
                startDate: startDate,
                endDate: endDate,
                deepMinutes: deepMinutes,
                remMinutes: remMinutes,
                coreMinutes: coreMinutes,
                awakeMinutes: awakeMinutes
            ))
        }
        try context.save()
    }

    func fetchAll() throws -> [SleepSessionRecord] {
        try context.fetch(FetchDescriptor<SleepSessionRecord>(sortBy: [SortDescriptor(\.startDate)]))
    }

    func fetchUnsynced() throws -> [SleepSessionRecord] {
        try fetchAll().filter { $0.syncState != .synced }
    }

    func updateSyncState(externalID: String, to state: SyncState) throws {
        guard let record = try fetchRecord(externalID: externalID) else { return }
        record.syncState = state
        try context.save()
    }

    private func fetchRecord(externalID: String) throws -> SleepSessionRecord? {
        let descriptor = FetchDescriptor<SleepSessionRecord>(
            predicate: #Predicate { $0.externalID == externalID }
        )
        return try context.fetch(descriptor).first
    }
}
