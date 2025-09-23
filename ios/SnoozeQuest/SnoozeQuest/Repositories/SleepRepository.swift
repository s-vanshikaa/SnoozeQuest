//
//  SleepRepository.swift
//  SnoozeQuest
//

import Foundation

protocol SleepRepository {
    func fetchDailySummaries(days: Int) async throws -> [DailySleepSummary]
    func fetchLatestSummary() async throws -> DailySleepSummary?
}

final class MockSleepRepository: SleepRepository {
    private let summaries: [DailySleepSummary]

    init(summaries: [DailySleepSummary] = MockSleepData.dailySummaries) {
        self.summaries = summaries
    }

    func fetchDailySummaries(days: Int) async throws -> [DailySleepSummary] {
        Array(summaries.suffix(days))
    }

    func fetchLatestSummary() async throws -> DailySleepSummary? {
        summaries.last
    }
}
