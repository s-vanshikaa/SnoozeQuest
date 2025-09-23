//
//  LeaderboardEntry.swift
//  SnoozeQuest
//

import Foundation

struct LeaderboardEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let rank: Int
    let displayName: String
    let averageSleepScore: Int
    let goalsCompleted: Int
    let isCurrentUser: Bool
}
