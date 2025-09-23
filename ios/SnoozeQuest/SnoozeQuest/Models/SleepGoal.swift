//
//  SleepGoal.swift
//  SnoozeQuest
//

import Foundation

struct TimeOfDay: Codable, Equatable {
    var hour: Int
    var minute: Int
}

struct SleepGoal: Codable, Equatable {
    var targetDuration: TimeInterval
    var bedtime: TimeOfDay
    var wakeTime: TimeOfDay
}
