//
//  FakeRepositories.swift
//  SnoozeQuestTests
//

import Foundation
@testable import SnoozeQuest

struct FakeSleepRepository: SleepRepository {
    let summaries: [DailySleepSummary]

    func fetchDailySummaries(days: Int) async throws -> [DailySleepSummary] {
        Array(summaries.suffix(days))
    }

    func fetchLatestSummary() async throws -> DailySleepSummary? {
        summaries.last
    }
}

actor FakeGoalRepository: GoalRepository {
    private var goal: SleepGoal
    private(set) var savedGoals: [SleepGoal] = []

    init(goal: SleepGoal) {
        self.goal = goal
    }

    func fetchGoal() async throws -> SleepGoal {
        goal
    }

    func saveGoal(_ goal: SleepGoal) async throws {
        self.goal = goal
        savedGoals.append(goal)
    }
}

struct FakeAnalyticsRepository: AnalyticsRepository {
    let analytics: SleepAnalytics

    func fetchAnalytics() async throws -> SleepAnalytics {
        analytics
    }
}

struct FakeLeaderboardRepository: LeaderboardRepository {
    let entries: [LeaderboardEntry]

    func fetchLeaderboard() async throws -> [LeaderboardEntry] {
        entries
    }
}

final class FakeHealthKitService: HealthKitServiceProtocol {
    var authorizationStatus: HealthKitAuthorizationStatus
    let statusAfterRequest: HealthKitAuthorizationStatus
    let sessionsToReturn: [SleepSession]

    init(
        authorizationStatus: HealthKitAuthorizationStatus,
        statusAfterRequest: HealthKitAuthorizationStatus,
        sessionsToReturn: [SleepSession] = []
    ) {
        self.authorizationStatus = authorizationStatus
        self.statusAfterRequest = statusAfterRequest
        self.sessionsToReturn = sessionsToReturn
    }

    func requestAuthorization() async -> HealthKitAuthorizationStatus {
        authorizationStatus = statusAfterRequest
        return authorizationStatus
    }

    func fetchRecentSleepSessions(days: Int) async throws -> [SleepSession] {
        sessionsToReturn
    }
}
