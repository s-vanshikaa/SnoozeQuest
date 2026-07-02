//
//  SleepScoreCalculator.swift
//  SnoozeQuest
//
//  Pure, deterministic mirror of the backend's sleep-score formula
//  (app/services/analytics.py, PRD §10: duration 50% / bedtime consistency
//  30% / goal adherence 20%). The backend has no per-day score endpoint, so
//  remote repositories compute each day's score client-side from the same
//  real session + goal data the backend itself would use.
//

import Foundation

enum SleepScoreCalculator {
    static let baselineSleepMinutes = 480

    static func bedtimeDeviationMinutes(startDate: Date, target: TimeOfDay, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: startDate)
        let actualMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let targetMinutes = target.hour * 60 + target.minute
        let diff = abs(actualMinutes - targetMinutes)
        return min(diff, 1440 - diff)
    }

    static func score(totalMinutes: Int, targetMinutes: Int, bedtimeDeviationMinutes: Int, goalMet: Bool) -> Int {
        let durationScore = min(100, Int((Double(totalMinutes) / Double(baselineSleepMinutes) * 100).rounded()))
        let bedtimeScore = max(0, 100 - bedtimeDeviationMinutes)
        let goalScore = goalMet ? 100 : 40
        let weighted = Double(durationScore) * 0.5 + Double(bedtimeScore) * 0.3 + Double(goalScore) * 0.2
        return Int(weighted.rounded())
    }
}
