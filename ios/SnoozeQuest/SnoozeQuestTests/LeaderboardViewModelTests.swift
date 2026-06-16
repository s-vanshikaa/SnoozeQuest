//
//  LeaderboardViewModelTests.swift
//  SnoozeQuestTests
//

import Testing
import Foundation
@testable import SnoozeQuest

@MainActor
struct LeaderboardViewModelTests {
    @Test func sortsEntriesByRankRegardlessOfRepositoryOrder() async {
        let entries = [
            LeaderboardEntry(id: UUID(), rank: 3, displayName: "C", averageSleepScore: 70, goalsCompleted: 2, isCurrentUser: false),
            LeaderboardEntry(id: UUID(), rank: 1, displayName: "A", averageSleepScore: 90, goalsCompleted: 5, isCurrentUser: false),
            LeaderboardEntry(id: UUID(), rank: 2, displayName: "B", averageSleepScore: 80, goalsCompleted: 3, isCurrentUser: true)
        ]
        let viewModel = LeaderboardViewModel(leaderboardRepository: FakeLeaderboardRepository(entries: entries))

        await viewModel.load()

        guard case .loaded(let sorted) = viewModel.state else {
            Issue.record("Expected loaded state")
            return
        }

        #expect(sorted.map(\.displayName) == ["A", "B", "C"])
    }

    @Test func emptyRepositoryProducesEmptyState() async {
        let viewModel = LeaderboardViewModel(leaderboardRepository: FakeLeaderboardRepository(entries: []))

        await viewModel.load()

        #expect(viewModel.state == .empty)
    }
}
