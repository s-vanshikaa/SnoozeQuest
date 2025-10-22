//
//  RemoteAnalyticsRepositoryTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

struct RemoteAnalyticsRepositoryTests {
    private static func makeSummary(goalMet: Bool) -> DailySleepSummary {
        DailySleepSummary(
            id: UUID(),
            date: Date(),
            session: SleepSession(id: UUID(), startDate: Date(), endDate: Date().addingTimeInterval(3600), stageDurations: [:]),
            sleepScore: 70,
            goalMet: goalMet
        )
    }

    @Test func fetchAnalyticsMapsAggregateFields() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/analytics", value: AnalyticsDTO(
            averageSleepMinutes: 420, averageSleepScore: 82.5, goalCompletionRate: 0.6,
            bedtimeConsistencyMinutes: 12, durationChangeMinutes: 5
        ))
        let sleepRepository = MockSleepRepository(summaries: [])
        let repository = RemoteAnalyticsRepository(apiClient: client, userID: 1, sleepRepository: sleepRepository)

        let analytics = try await repository.fetchAnalytics()

        #expect(analytics.averageSleepScore == 83)
        #expect(analytics.averageDuration == 420 * 60)
    }

    @Test func fetchAnalyticsComputesCurrentStreakFromMostRecentTrend() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/analytics", value: AnalyticsDTO(
            averageSleepMinutes: 420, averageSleepScore: 80, goalCompletionRate: 0.6,
            bedtimeConsistencyMinutes: 12, durationChangeMinutes: 5
        ))
        // Oldest -> newest: miss, hit, hit. Streak should count only the trailing hits.
        let trend = [Self.makeSummary(goalMet: false), Self.makeSummary(goalMet: true), Self.makeSummary(goalMet: true)]
        let sleepRepository = MockSleepRepository(summaries: trend)
        let repository = RemoteAnalyticsRepository(apiClient: client, userID: 1, sleepRepository: sleepRepository)

        let analytics = try await repository.fetchAnalytics()

        #expect(analytics.currentStreak == 2)
        #expect(analytics.sevenDayTrend.count == 3)
    }
}
