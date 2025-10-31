//
//  SleepSessionRecord.swift
//  SnoozeQuest
//

import Foundation
import SwiftData

enum SyncState: String, Codable {
    case pending
    case synced
    case failed
}

@Model
final class SleepSessionRecord {
    @Attribute(.unique) var externalID: String
    var startDate: Date
    var endDate: Date
    var deepMinutes: Int
    var remMinutes: Int
    var coreMinutes: Int
    var awakeMinutes: Int
    var syncState: SyncState

    init(
        externalID: String,
        startDate: Date,
        endDate: Date,
        deepMinutes: Int,
        remMinutes: Int,
        coreMinutes: Int,
        awakeMinutes: Int,
        syncState: SyncState = .pending
    ) {
        self.externalID = externalID
        self.startDate = startDate
        self.endDate = endDate
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.coreMinutes = coreMinutes
        self.awakeMinutes = awakeMinutes
        self.syncState = syncState
    }
}
