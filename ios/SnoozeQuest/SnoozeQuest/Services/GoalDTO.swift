//
//  GoalDTO.swift
//  SnoozeQuest
//

import Foundation

struct GoalDTO: Decodable {
    let id: Int
    let userId: Int
    let targetMinutes: Int
    let targetBedtime: String
    let targetWakeTime: String
    let updatedAt: Date
}

struct GoalUpdateDTO: Codable {
    let userId: Int
    let targetMinutes: Int
    let targetBedtime: String
    let targetWakeTime: String
}
