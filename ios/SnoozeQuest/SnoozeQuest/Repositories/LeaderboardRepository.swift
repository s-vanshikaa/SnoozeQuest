//
//  LeaderboardRepository.swift
//  SnoozeQuest
//

import Foundation

protocol LeaderboardRepository {
    func fetchLeaderboard() async throws -> [LeaderboardEntry]
}

final class MockLeaderboardRepository: LeaderboardRepository {
    private let entries: [LeaderboardEntry]

    init(entries: [LeaderboardEntry] = MockSleepData.leaderboard) {
        self.entries = entries
    }

    func fetchLeaderboard() async throws -> [LeaderboardEntry] {
        entries
    }
}

final class RemoteLeaderboardRepository: LeaderboardRepository {
    private let apiClient: APIClientProtocol
    private let currentUserID: Int?

    init(apiClient: APIClientProtocol, currentUserID: Int? = nil) {
        self.apiClient = apiClient
        self.currentUserID = currentUserID
    }

    func fetchLeaderboard() async throws -> [LeaderboardEntry] {
        let entries: [LeaderboardEntryDTO] = try await apiClient.request(Endpoint(path: "/api/v1/leaderboard"))

        return entries.map { dto in
            LeaderboardEntry(
                id: UUID(backendID: dto.id),
                rank: dto.rank,
                displayName: dto.name,
                averageSleepScore: Int(dto.averageScore.rounded()),
                goalsCompleted: dto.goalsMet,
                isCurrentUser: dto.id == currentUserID
            )
        }
    }
}
