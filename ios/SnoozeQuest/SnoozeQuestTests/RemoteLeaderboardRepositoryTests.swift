//
//  RemoteLeaderboardRepositoryTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

struct RemoteLeaderboardRepositoryTests {
    @Test func fetchLeaderboardMapsEntriesAndMarksCurrentUser() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/leaderboard", value: [
            LeaderboardEntryDTO(id: 1, name: "Ava", rank: 1, averageScore: 88.4, goalsMet: 5),
            LeaderboardEntryDTO(id: 2, name: "Liam", rank: 2, averageScore: 75.0, goalsMet: 3),
        ])
        let repository = RemoteLeaderboardRepository(apiClient: client, currentUserID: 2)

        let entries = try await repository.fetchLeaderboard()

        #expect(entries.count == 2)
        #expect(entries[0].averageSleepScore == 88)
        #expect(entries[0].isCurrentUser == false)
        #expect(entries[1].isCurrentUser == true)
        #expect(entries[1].goalsCompleted == 3)
    }

    @Test func fetchLeaderboardWithoutCurrentUserIDMarksNoOne() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/leaderboard", value: [
            LeaderboardEntryDTO(id: 1, name: "Ava", rank: 1, averageScore: 88.0, goalsMet: 5),
        ])
        let repository = RemoteLeaderboardRepository(apiClient: client)

        let entries = try await repository.fetchLeaderboard()

        #expect(entries[0].isCurrentUser == false)
    }
}
