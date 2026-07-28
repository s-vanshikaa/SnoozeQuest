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

final class RemoteAnalyticsRepository: AnalyticsRepository {
    private static let trendDays = 7

    private let apiClient: APIClientProtocol
    private let userID: Int
    private let sleepRepository: SleepRepository

    init(apiClient: APIClientProtocol, userID: Int, sleepRepository: SleepRepository) {
        self.apiClient = apiClient
        self.userID = userID
        self.sleepRepository = sleepRepository
    }

    func fetchAnalytics() async throws -> SleepAnalytics {
        let endpoint = Endpoint(path: "/api/v1/analytics", queryItems: [
            URLQueryItem(name: "user_id", value: String(userID)),
            URLQueryItem(name: "days", value: String(Self.trendDays)),
        ])
        async let analyticsDTO: AnalyticsDTO = apiClient.request(endpoint)
        async let trend = sleepRepository.fetchDailySummaries(days: Self.trendDays)

        let (dto, sevenDayTrend) = try await (analyticsDTO, trend)

        return SleepAnalytics(
            averageSleepScore: Int(dto.averageSleepScore.rounded()),
            averageDuration: TimeInterval(dto.averageSleepMinutes * 60),
            currentStreak: Self.currentStreak(from: sevenDayTrend),
            sevenDayTrend: sevenDayTrend
        )
    }

    private static func currentStreak(from trend: [DailySleepSummary]) -> Int {
        trend.reversed().prefix { $0.goalMet }.count
    }
}
