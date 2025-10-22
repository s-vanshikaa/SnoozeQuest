//
//  LeaderboardDTO.swift
//  SnoozeQuest
//

import Foundation

struct LeaderboardEntryDTO: Decodable {
    let id: Int
    let name: String
    let rank: Int
    let averageScore: Double
    let goalsMet: Int
}
