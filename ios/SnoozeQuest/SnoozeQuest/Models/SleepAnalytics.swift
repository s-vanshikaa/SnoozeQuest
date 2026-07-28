//
//  SleepAnalytics.swift
//  SnoozeQuest
//

import Foundation

struct SleepAnalytics: Codable, Equatable {
    var averageSleepScore: Int
    var averageDuration: TimeInterval
    var currentStreak: Int
    var sevenDayTrend: [DailySleepSummary]
}
