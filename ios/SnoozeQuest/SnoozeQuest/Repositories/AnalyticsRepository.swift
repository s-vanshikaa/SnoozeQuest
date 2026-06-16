//
//  AnalyticsRepository.swift
//  SnoozeQuest
//

import Foundation

protocol AnalyticsRepository {
    func fetchAnalytics() async throws -> SleepAnalytics
}

final class MockAnalyticsRepository: AnalyticsRepository {
    private let analytics: SleepAnalytics

    init(analytics: SleepAnalytics = MockSleepData.analytics) {
        self.analytics = analytics
    }

    func fetchAnalytics() async throws -> SleepAnalytics {
        analytics
    }
}
