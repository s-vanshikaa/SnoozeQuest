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
