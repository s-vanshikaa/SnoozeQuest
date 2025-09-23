//
//  SleepSession.swift
//  SnoozeQuest
//

import Foundation

enum SleepStage: String, Codable, CaseIterable, Equatable {
    case awake
    case rem
    case core
    case deep
}

struct SleepSession: Identifiable, Codable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let stageDurations: [SleepStage: TimeInterval]

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
}
