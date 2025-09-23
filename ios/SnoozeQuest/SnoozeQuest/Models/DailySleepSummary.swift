//
//  DailySleepSummary.swift
//  SnoozeQuest
//

import Foundation

struct DailySleepSummary: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let session: SleepSession
    let sleepScore: Int
    let goalMet: Bool
}
