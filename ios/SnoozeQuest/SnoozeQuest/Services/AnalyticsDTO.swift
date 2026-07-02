//
//  AnalyticsDTO.swift
//  SnoozeQuest
//

import Foundation

struct AnalyticsDTO: Decodable {
    let averageSleepMinutes: Double
    let averageSleepScore: Double
    let goalCompletionRate: Double
    let bedtimeConsistencyMinutes: Double
    let durationChangeMinutes: Double
}
