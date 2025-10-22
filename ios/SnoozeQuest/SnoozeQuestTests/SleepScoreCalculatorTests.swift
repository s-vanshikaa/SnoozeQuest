//
//  SleepScoreCalculatorTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

struct SleepScoreCalculatorTests {
    @Test func bedtimeDeviationIsZeroForExactMatch() {
        let calendar = utcCalendar()
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 0))!

        let deviation = SleepScoreCalculator.bedtimeDeviationMinutes(
            startDate: start, target: TimeOfDay(hour: 23, minute: 0), calendar: calendar
        )

        #expect(deviation == 0)
    }

    @Test func bedtimeDeviationHandlesMidnightWraparound() {
        let calendar = utcCalendar()
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 23, minute: 50))!

        let deviation = SleepScoreCalculator.bedtimeDeviationMinutes(
            startDate: start, target: TimeOfDay(hour: 0, minute: 10), calendar: calendar
        )

        #expect(deviation == 20)
    }

    @Test func scoreIsMaximalForFullDurationOnTimeGoalMet() {
        let score = SleepScoreCalculator.score(totalMinutes: 480, targetMinutes: 480, bedtimeDeviationMinutes: 0, goalMet: true)
        #expect(score == 100)
    }

    @Test func scoreIsLowerForShortDurationAndMissedGoal() {
        let shortScore = SleepScoreCalculator.score(totalMinutes: 200, targetMinutes: 480, bedtimeDeviationMinutes: 0, goalMet: false)
        let fullScore = SleepScoreCalculator.score(totalMinutes: 480, targetMinutes: 480, bedtimeDeviationMinutes: 0, goalMet: true)
        #expect(shortScore < fullScore)
    }

    @Test func scoreIsBoundedBetweenZeroAndHundred() {
        let score = SleepScoreCalculator.score(totalMinutes: 0, targetMinutes: 480, bedtimeDeviationMinutes: 1000, goalMet: false)
        #expect(score >= 0 && score <= 100)
    }
}
