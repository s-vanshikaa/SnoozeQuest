//
//  AppEnvironment.swift
//  SnoozeQuest
//

import Foundation

enum AppEnvironment {
    static let baseURL = URL(string: "http://localhost:8000")!
    static let currentUserID = 1

    static let apiClient: APIClientProtocol = APIClient(baseURL: baseURL)

    static let goalRepository: GoalRepository = RemoteGoalRepository(apiClient: apiClient, userID: currentUserID)
    static let sleepRepository: SleepRepository = RemoteSleepRepository(
        apiClient: apiClient, userID: currentUserID, goalRepository: goalRepository
    )
    static let analyticsRepository: AnalyticsRepository = RemoteAnalyticsRepository(
        apiClient: apiClient, userID: currentUserID, sleepRepository: sleepRepository
    )
    static let leaderboardRepository: LeaderboardRepository = RemoteLeaderboardRepository(
        apiClient: apiClient, currentUserID: currentUserID
    )

    static let healthKitService: HealthKitServiceProtocol = HealthKitService()
}
