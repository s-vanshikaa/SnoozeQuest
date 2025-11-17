//
//  AppEnvironment.swift
//  SnoozeQuest
//

import Foundation
import SwiftData

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
    static let weeklyInsightRepository: WeeklyInsightRepository = RemoteWeeklyInsightRepository(
        apiClient: apiClient, userID: currentUserID
    )

    static let healthKitService: HealthKitServiceProtocol = HealthKitService()
    static let notificationService: NotificationServiceProtocol = NotificationService()

    static let modelContainer: ModelContainer = try! ModelContainer(for: Schema([SleepSessionRecord.self]))
    static let sleepSessionStore: SleepSessionStore = SwiftDataSleepSessionStore(
        context: ModelContext(modelContainer)
    )

    static let healthKitImportService = HealthKitImportService(
        healthKitService: healthKitService, sleepSessionStore: sleepSessionStore
    )
    static let syncEngine = SyncEngine(apiClient: apiClient, sleepSessionStore: sleepSessionStore, userID: currentUserID)

    static let backgroundRefreshService = BackgroundRefreshService(
        healthKitImportService: healthKitImportService, syncEngine: syncEngine
    )
}
