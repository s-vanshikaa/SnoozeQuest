//
//  WeeklyInsight.swift
//  SnoozeQuest
//

import Foundation

struct WeeklyInsightMetrics: Equatable {
    let averageSleepMinutes: Double
    let durationChangeMinutes: Double
    let bedtimeChangeMinutes: Double
    let goalCompletionRate: Double
    let averageSleepScore: Double
}

struct WeeklyInsight: Equatable {
    let weekStartDate: Date
    let metrics: WeeklyInsightMetrics
    let summaryText: String?
}
