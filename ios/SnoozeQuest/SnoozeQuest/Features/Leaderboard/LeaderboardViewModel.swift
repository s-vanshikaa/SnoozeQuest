//
//  LeaderboardViewModel.swift
//  SnoozeQuest
//

import Combine
import Foundation

@MainActor
final class LeaderboardViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([LeaderboardEntry])
        case empty
        case error(String)
    }

    @Published private(set) var state: State = .loading

    private let leaderboardRepository: LeaderboardRepository

    init(leaderboardRepository: LeaderboardRepository = MockLeaderboardRepository()) {
        self.leaderboardRepository = leaderboardRepository
    }

    func load() async {
        state = .loading
        do {
            let entries = try await leaderboardRepository.fetchLeaderboard()
            guard !entries.isEmpty else {
                state = .empty
                return
            }
            state = .loaded(entries.sorted { $0.rank < $1.rank })
        } catch {
            state = .error("We couldn't load the leaderboard. Pull to refresh to try again.")
        }
    }

    convenience init(previewState: State) {
        self.init()
        state = previewState
    }
}
