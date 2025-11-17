//
//  WeeklyInsightViewModelTests.swift
//  SnoozeQuestTests
//

import Testing
@testable import SnoozeQuest

@MainActor
struct WeeklyInsightViewModelTests {
    @Test func loadSetsAvailableStateOnSuccess() async {
        let insight = MockSleepData.weeklyInsight
        let viewModel = WeeklyInsightViewModel(weeklyInsightRepository: FakeWeeklyInsightRepository(insight: insight))

        await viewModel.load()

        #expect(viewModel.state == .available(insight))
    }

    @Test func loadSetsUnavailableStateOnFailure() async {
        let viewModel = WeeklyInsightViewModel(
            weeklyInsightRepository: FakeWeeklyInsightRepository(errorToThrow: APIError.timeout)
        )

        await viewModel.load()

        #expect(viewModel.state == .unavailable)
    }
}
