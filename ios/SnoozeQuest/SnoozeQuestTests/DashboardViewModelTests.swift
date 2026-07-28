//
//  DashboardViewModelTests.swift
//  SnoozeQuestTests
//

import Testing
import Foundation
@testable import SnoozeQuest

@MainActor
struct DashboardViewModelTests {
    @Test func loadedStatePopulatesDisplayModelFromRepositories() async {
        let start = Date(timeIntervalSince1970: 0)
        let session = SleepSession(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(8 * 3600),
            stageDurations: [.awake: 1800, .rem: 5400, .core: 18000, .deep: 3600]
        )
        let summary = DailySleepSummary(id: UUID(), date: start, session: session, sleepScore: 88, goalMet: true)
        let goal = SleepGoal(targetDuration: 8 * 3600, bedtime: TimeOfDay(hour: 22, minute: 30), wakeTime: TimeOfDay(hour: 6, minute: 30))
        let analytics = SleepAnalytics(
            averageSleepScore: 80,
            averageDuration: 7.5 * 3600,
            currentStreak: 4,
            sevenDayTrend: [summary]
        )

        let viewModel = DashboardViewModel(
            sleepRepository: FakeSleepRepository(summaries: [summary]),
            goalRepository: FakeGoalRepository(goal: goal),
            analyticsRepository: FakeAnalyticsRepository(analytics: analytics)
        )

        await viewModel.load()

        guard case .loaded(let display) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }

        #expect(display.sleepScore == 88)
        #expect(display.goalProgress == 1.0)
        #expect(display.sevenDayTrend.count == 1)
        #expect(display.stageBreakdown.count == 4)
    }

    @Test func emptyRepositoryProducesEmptyState() async {
        let goal = SleepGoal(targetDuration: 8 * 3600, bedtime: TimeOfDay(hour: 22, minute: 30), wakeTime: TimeOfDay(hour: 6, minute: 30))
        let analytics = SleepAnalytics(averageSleepScore: 0, averageDuration: 0, currentStreak: 0, sevenDayTrend: [])

        let viewModel = DashboardViewModel(
            sleepRepository: FakeSleepRepository(summaries: []),
            goalRepository: FakeGoalRepository(goal: goal),
            analyticsRepository: FakeAnalyticsRepository(analytics: analytics)
        )

        await viewModel.load()

        #expect(viewModel.state == .empty)
    }
}
