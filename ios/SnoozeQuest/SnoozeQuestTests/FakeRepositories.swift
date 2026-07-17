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
    var errorToThrow: Error?

    init(
        authorizationStatus: HealthKitAuthorizationStatus,
        statusAfterRequest: HealthKitAuthorizationStatus,
        sessionsToReturn: [SleepSession] = [],
        errorToThrow: Error? = nil
    ) {
        self.authorizationStatus = authorizationStatus
        self.statusAfterRequest = statusAfterRequest
        self.sessionsToReturn = sessionsToReturn
        self.errorToThrow = errorToThrow
    }

    func requestAuthorization() async -> HealthKitAuthorizationStatus {
        authorizationStatus = statusAfterRequest
        return authorizationStatus
    }

    func fetchRecentSleepSessions(days: Int) async throws -> [SleepSession] {
        if let errorToThrow {
            throw errorToThrow
        }
        return sessionsToReturn
    }
}

final class FakeNotificationService: NotificationServiceProtocol {
    var status: NotificationAuthorizationStatus
    let statusAfterRequest: NotificationAuthorizationStatus
    private(set) var scheduledBedtimes: [TimeOfDay] = []
    private(set) var bedtimeReminderCancelled = false
    private(set) var weeklySummarySchedCount = 0
    private(set) var weeklySummaryReminderCancelled = false

    init(
        status: NotificationAuthorizationStatus = .authorized,
        statusAfterRequest: NotificationAuthorizationStatus = .authorized
    ) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> NotificationAuthorizationStatus {
        status = statusAfterRequest
        return status
    }

    func scheduleBedtimeReminder(bedtime: TimeOfDay) async throws {
        scheduledBedtimes.append(bedtime)
    }

    func cancelBedtimeReminder() async {
        bedtimeReminderCancelled = true
    }

    func scheduleWeeklySummaryReminder() async throws {
        weeklySummarySchedCount += 1
    }

    func cancelWeeklySummaryReminder() async {
        weeklySummaryReminderCancelled = true
    }
}
