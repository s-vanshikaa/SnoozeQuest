//
//  WeeklyInsightDTO.swift
//  SnoozeQuest
//

import Foundation

struct WeeklyInsightMetricsDTO: Decodable {
    let averageSleepMinutes: Double
    let durationChangeMinutes: Double
    let bedtimeChangeMinutes: Double
    let goalCompletionRate: Double
    let averageSleepScore: Double
}

struct WeeklyInsightDTO: Decodable {
    let weekStartDate: String
    let metrics: WeeklyInsightMetricsDTO
    let summaryText: String?
}
