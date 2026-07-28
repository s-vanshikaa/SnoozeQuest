//
//  WeeklyInsightRepository.swift
//  SnoozeQuest
//

import Foundation

protocol WeeklyInsightRepository {
    func fetchWeeklyInsight() async throws -> WeeklyInsight
}

final class MockWeeklyInsightRepository: WeeklyInsightRepository {
    private let insight: WeeklyInsight

    init(insight: WeeklyInsight = MockSleepData.weeklyInsight) {
        self.insight = insight
    }

    func fetchWeeklyInsight() async throws -> WeeklyInsight {
        insight
    }
}

final class RemoteWeeklyInsightRepository: WeeklyInsightRepository {
    private let apiClient: APIClientProtocol
    private let userID: Int

    init(apiClient: APIClientProtocol, userID: Int) {
        self.apiClient = apiClient
        self.userID = userID
    }

    func fetchWeeklyInsight() async throws -> WeeklyInsight {
        let endpoint = Endpoint(path: "/api/v1/insights", queryItems: [
            URLQueryItem(name: "user_id", value: String(userID)),
        ])
        let dto: WeeklyInsightDTO = try await apiClient.request(endpoint)
        return Self.makeWeeklyInsight(from: dto)
    }

    private static func makeWeeklyInsight(from dto: WeeklyInsightDTO) -> WeeklyInsight {
        WeeklyInsight(
            weekStartDate: UTCDayFormatter.shared.date(from: dto.weekStartDate) ?? Date(),
            metrics: WeeklyInsightMetrics(
                averageSleepMinutes: dto.metrics.averageSleepMinutes,
                durationChangeMinutes: dto.metrics.durationChangeMinutes,
                bedtimeChangeMinutes: dto.metrics.bedtimeChangeMinutes,
                goalCompletionRate: dto.metrics.goalCompletionRate,
                averageSleepScore: dto.metrics.averageSleepScore
            ),
            summaryText: dto.summaryText
        )
    }
}
