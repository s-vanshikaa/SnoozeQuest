//
//  RemoteWeeklyInsightRepositoryTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

struct RemoteWeeklyInsightRepositoryTests {
    @Test func fetchWeeklyInsightMapsDTOToDomainModel() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/insights", value: WeeklyInsightDTO(
            weekStartDate: "2026-08-10",
            metrics: WeeklyInsightMetricsDTO(
                averageSleepMinutes: 444.5,
                durationChangeMinutes: -21.8,
                bedtimeChangeMinutes: -13.75,
                goalCompletionRate: 0.42,
                averageSleepScore: 83.9
            ),
            summaryText: "You averaged around 7h 24m this week."
        ))
        let repository = RemoteWeeklyInsightRepository(apiClient: client, userID: 1)

        let insight = try await repository.fetchWeeklyInsight()

        #expect(insight.weekStartDate == utcDate(2026, 8, 10, 0, 0))
        #expect(insight.metrics.averageSleepMinutes == 444.5)
        #expect(insight.metrics.durationChangeMinutes == -21.8)
        #expect(insight.metrics.bedtimeChangeMinutes == -13.75)
        #expect(insight.metrics.goalCompletionRate == 0.42)
        #expect(insight.metrics.averageSleepScore == 83.9)
        #expect(insight.summaryText == "You averaged around 7h 24m this week.")
    }

    @Test func fetchWeeklyInsightPassesThroughANilSummaryText() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/insights", value: WeeklyInsightDTO(
            weekStartDate: "2026-08-10",
            metrics: WeeklyInsightMetricsDTO(
                averageSleepMinutes: 400, durationChangeMinutes: 0, bedtimeChangeMinutes: 0,
                goalCompletionRate: 0, averageSleepScore: 70
            ),
            summaryText: nil
        ))
        let repository = RemoteWeeklyInsightRepository(apiClient: client, userID: 1)

        let insight = try await repository.fetchWeeklyInsight()

        #expect(insight.summaryText == nil)
    }

    @Test func fetchWeeklyInsightIncludesUserIDQueryItem() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/insights", value: WeeklyInsightDTO(
            weekStartDate: "2026-08-10",
            metrics: WeeklyInsightMetricsDTO(
                averageSleepMinutes: 0, durationChangeMinutes: 0, bedtimeChangeMinutes: 0,
                goalCompletionRate: 0, averageSleepScore: 0
            ),
            summaryText: nil
        ))
        let repository = RemoteWeeklyInsightRepository(apiClient: client, userID: 42)

        _ = try await repository.fetchWeeklyInsight()

        let queryItems = client.requestedEndpoints.first?.queryItems ?? []
        #expect(queryItems.contains(URLQueryItem(name: "user_id", value: "42")))
    }
}
