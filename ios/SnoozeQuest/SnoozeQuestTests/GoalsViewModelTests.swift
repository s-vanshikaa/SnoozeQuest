//
//  GoalsViewModelTests.swift
//  SnoozeQuestTests
//

import Testing
import Foundation
@testable import SnoozeQuest

@MainActor
struct GoalsViewModelTests {
    private static let sampleGoal = SleepGoal(
        targetDuration: 8 * 3600,
        bedtime: TimeOfDay(hour: 22, minute: 30),
        wakeTime: TimeOfDay(hour: 6, minute: 30)
    )

    private static let sampleAnalytics = SleepAnalytics(
        averageSleepScore: 80,
        averageDuration: 8 * 3600,
        currentStreak: 3,
        sevenDayTrend: []
    )

    @Test func rejectsZeroDuration() async {
        let repository = FakeGoalRepository(goal: Self.sampleGoal)
        let viewModel = GoalsViewModel(
            goalRepository: repository,
            sleepRepository: FakeSleepRepository(summaries: []),
            analyticsRepository: FakeAnalyticsRepository(analytics: Self.sampleAnalytics)
        )
        await viewModel.load()

        viewModel.targetDuration = 0
        await viewModel.save()

        #expect(viewModel.validationMessage != nil)
        #expect(await repository.savedGoals.isEmpty)
    }

    @Test func rejectsDurationOverSixteenHours() async {
        let repository = FakeGoalRepository(goal: Self.sampleGoal)
        let viewModel = GoalsViewModel(
            goalRepository: repository,
            sleepRepository: FakeSleepRepository(summaries: []),
            analyticsRepository: FakeAnalyticsRepository(analytics: Self.sampleAnalytics)
        )
        await viewModel.load()

        viewModel.targetDuration = 17 * 3600
        await viewModel.save()

        #expect(viewModel.validationMessage != nil)
        #expect(await repository.savedGoals.isEmpty)
    }

    @Test func acceptsValidDurationAndSavesThroughRepository() async {
        let repository = FakeGoalRepository(goal: Self.sampleGoal)
        let viewModel = GoalsViewModel(
            goalRepository: repository,
            sleepRepository: FakeSleepRepository(summaries: []),
            analyticsRepository: FakeAnalyticsRepository(analytics: Self.sampleAnalytics)
        )
        await viewModel.load()

        viewModel.targetDuration = TimeInterval(7 * 3600 + 30 * 60)
        await viewModel.save()

        #expect(viewModel.validationMessage == nil)
        #expect(viewModel.didSave == true)

        let saved = await repository.savedGoals
        #expect(saved.count == 1)
        #expect(saved.first?.targetDuration == TimeInterval(7 * 3600 + 30 * 60))
    }

    @Test func completionPercentageAndStreakReflectAnalytics() async {
        let start = Date(timeIntervalSince1970: 0)
        let metSummary = DailySleepSummary(
            id: UUID(),
            date: start,
            session: SleepSession(id: UUID(), startDate: start, endDate: start.addingTimeInterval(8 * 3600), stageDurations: [:]),
            sleepScore: 90,
            goalMet: true
        )
        let missedSummary = DailySleepSummary(
            id: UUID(),
            date: start.addingTimeInterval(86400),
            session: SleepSession(id: UUID(), startDate: start, endDate: start.addingTimeInterval(5 * 3600), stageDurations: [:]),
            sleepScore: 50,
            goalMet: false
        )

        let viewModel = GoalsViewModel(
            goalRepository: FakeGoalRepository(goal: Self.sampleGoal),
            sleepRepository: FakeSleepRepository(summaries: [metSummary, missedSummary]),
            analyticsRepository: FakeAnalyticsRepository(analytics: Self.sampleAnalytics)
        )

        await viewModel.load()

        guard case .loaded(let display) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }

        #expect(display.completionPercentageText == "50%")
        #expect(display.streakCount == 3)
    }

    @Test func nextWorldTextReflectsJourneyProgress() async {
        let summaries = (0..<5).map { offset -> DailySleepSummary in
            let date = Date(timeIntervalSince1970: 0).addingTimeInterval(Double(offset) * 86400)
            let session = SleepSession(id: UUID(), startDate: date, endDate: date.addingTimeInterval(8 * 3600), stageDurations: [:])
            return DailySleepSummary(id: UUID(), date: date, session: session, sleepScore: 85, goalMet: true)
        }

        let viewModel = GoalsViewModel(
            goalRepository: FakeGoalRepository(goal: Self.sampleGoal),
            sleepRepository: FakeSleepRepository(summaries: summaries),
            analyticsRepository: FakeAnalyticsRepository(analytics: Self.sampleAnalytics)
        )

        await viewModel.load()

        guard case .loaded(let display) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }

        // 5 goal-met nights -> past Mars's threshold (4), 4 nights until Venus (9).
        #expect(display.nextWorldText == "4 goal nights until Venus")
    }
}
