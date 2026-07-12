//
//  RemoteSleepRepositoryTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

struct RemoteSleepRepositoryTests {
    private static let goal = SleepGoal(
        targetDuration: 480 * 60,
        bedtime: TimeOfDay(hour: 23, minute: 0),
        wakeTime: TimeOfDay(hour: 7, minute: 0)
    )

    @Test func fetchDailySummariesMapsSessionAndComputesGoalMetScore() async throws {
        let client = FakeAPIClient()
        let start = utcDate(2026, 1, 1, 23, 0)
        let end = start.addingTimeInterval(500 * 60)
        client.stub(path: "/api/v1/sleep", value: [
            SleepSessionDTO(
                id: 1, userId: 1, externalId: "x", startTime: start, endTime: end,
                deepMinutes: 100, remMinutes: 120, coreMinutes: 280, awakeMinutes: 20, createdAt: Date()
            ),
        ])
        let repository = RemoteSleepRepository(
            apiClient: client, userID: 1, goalRepository: MockGoalRepository(goal: Self.goal)
        )

        let summaries = try await repository.fetchDailySummaries(days: 7)

        #expect(summaries.count == 1)
        let summary = summaries[0]
        #expect(summary.goalMet == true) // 100+120+280 = 500 >= 480 target
        let expectedDeepDuration = TimeInterval(6000)
        #expect(summary.session.stageDurations[.deep] == expectedDeepDuration)
        #expect(summary.session.startDate == start)
        #expect(summary.sleepScore == SleepScoreCalculator.score(
            totalMinutes: 500, targetMinutes: 480, bedtimeDeviationMinutes: 0, goalMet: true
        ))
    }

    @Test func fetchDailySummariesMarksGoalNotMetForShortSession() async throws {
        let client = FakeAPIClient()
        let start = utcDate(2026, 1, 1, 23, 0)
        client.stub(path: "/api/v1/sleep", value: [
            SleepSessionDTO(
                id: 1, userId: 1, externalId: "x", startTime: start, endTime: start.addingTimeInterval(300 * 60),
                deepMinutes: 50, remMinutes: 50, coreMinutes: 150, awakeMinutes: 50, createdAt: Date()
            ),
        ])
        let repository = RemoteSleepRepository(
            apiClient: client, userID: 1, goalRepository: MockGoalRepository(goal: Self.goal)
        )

        let summaries = try await repository.fetchDailySummaries(days: 7)

        #expect(summaries[0].goalMet == false) // 50+50+150 = 250 < 480 target
    }

    @Test func fetchDailySummariesIncludesUserIDAndDateRangeQueryItems() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/sleep", value: [SleepSessionDTO]())
        let repository = RemoteSleepRepository(
            apiClient: client, userID: 99, goalRepository: MockGoalRepository(goal: Self.goal)
        )

        _ = try await repository.fetchDailySummaries(days: 7)

        let queryItems = client.requestedEndpoints.first?.queryItems ?? []
        #expect(queryItems.contains(URLQueryItem(name: "user_id", value: "99")))
        #expect(queryItems.contains { $0.name == "start_date" })
        #expect(queryItems.contains { $0.name == "end_date" })
    }

    @Test func fetchLatestSummaryReturnsNilWhenNoSessionsExist() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/sleep", value: [SleepSessionDTO]())
        let repository = RemoteSleepRepository(
            apiClient: client, userID: 1, goalRepository: MockGoalRepository(goal: Self.goal)
        )

        let summary = try await repository.fetchLatestSummary()

        #expect(summary == nil)
    }

    @Test func fetchLatestSummaryFindsSessionFromSeveralDaysAgo() async throws {
        // Regression test: fetchLatestSummary must not be restricted to "today only" —
        // otherwise it would report no data whenever the user hasn't synced yet today,
        // even though recent data exists from a prior day.
        let client = FakeAPIClient()
        let staleStart = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        client.stub(path: "/api/v1/sleep", value: [
            SleepSessionDTO(
                id: 7, userId: 1, externalId: "stale", startTime: staleStart,
                endTime: staleStart.addingTimeInterval(480 * 60),
                deepMinutes: 100, remMinutes: 120, coreMinutes: 260, awakeMinutes: 20, createdAt: Date()
            ),
        ])
        let repository = RemoteSleepRepository(
            apiClient: client, userID: 1, goalRepository: MockGoalRepository(goal: Self.goal)
        )

        let summary = try await repository.fetchLatestSummary()

        #expect(summary?.session.id == UUID(backendID: 7))
    }
}
