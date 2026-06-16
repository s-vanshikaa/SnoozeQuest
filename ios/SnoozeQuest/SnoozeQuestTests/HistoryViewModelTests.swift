//
//  HistoryViewModelTests.swift
//  SnoozeQuestTests
//

import Testing
import Foundation
@testable import SnoozeQuest

@MainActor
struct HistoryViewModelTests {
    @Test func weekSelectionRequestsSevenDaysOfData() async {
        let summaries = (0..<30).map { makeSummary(dayOffset: $0) }
        let viewModel = HistoryViewModel(sleepRepository: FakeSleepRepository(summaries: summaries))

        viewModel.selectedRange = .week
        await viewModel.load()

        guard case .loaded(let display) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }

        #expect(display.dayPoints.count == 7)
        #expect(display.sessionRows.count == 7)
    }

    @Test func monthSelectionRequestsThirtyDaysOfData() async {
        let summaries = (0..<30).map { makeSummary(dayOffset: $0) }
        let viewModel = HistoryViewModel(sleepRepository: FakeSleepRepository(summaries: summaries))

        viewModel.selectedRange = .month
        await viewModel.load()

        guard case .loaded(let display) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }

        #expect(display.dayPoints.count == 30)
        #expect(display.sessionRows.count == 30)
    }

    @Test func averageDurationIsFormattedAsHoursAndMinutes() async {
        let start = Date(timeIntervalSince1970: 0)
        let session = SleepSession(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(8 * 3600 + 20 * 60),
            stageDurations: [:]
        )
        let summary = DailySleepSummary(id: UUID(), date: start, session: session, sleepScore: 80, goalMet: true)
        let viewModel = HistoryViewModel(sleepRepository: FakeSleepRepository(summaries: [summary]))

        await viewModel.load()

        guard case .loaded(let display) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }

        #expect(display.averageDurationText == "8h 20m")
        #expect(display.sessionRows.first?.durationText == "8h 20m")
    }

    @Test func stagePercentagesSumToWholeForEachDay() async {
        let start = Date(timeIntervalSince1970: 0)
        let session = SleepSession(
            id: UUID(),
            startDate: start,
            endDate: start.addingTimeInterval(8 * 3600),
            stageDurations: [.awake: 1800, .rem: 5400, .core: 18000, .deep: 3600]
        )
        let summary = DailySleepSummary(id: UUID(), date: start, session: session, sleepScore: 80, goalMet: true)
        let viewModel = HistoryViewModel(sleepRepository: FakeSleepRepository(summaries: [summary]))

        await viewModel.load()

        guard case .loaded(let display) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }

        let total = display.dayPoints.first?.stagePercentages.values.reduce(0, +) ?? 0
        #expect(abs(total - 1.0) < 0.001)
    }
}

private func makeSummary(dayOffset: Int) -> DailySleepSummary {
    let date = Date(timeIntervalSince1970: 0).addingTimeInterval(Double(dayOffset) * 86400)
    let session = SleepSession(id: UUID(), startDate: date, endDate: date.addingTimeInterval(8 * 3600), stageDurations: [:])
    return DailySleepSummary(id: UUID(), date: date, session: session, sleepScore: 75, goalMet: true)
}
