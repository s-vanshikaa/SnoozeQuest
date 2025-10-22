//
//  SleepDTO.swift
//  SnoozeQuest
//

import Foundation

struct SleepSessionDTO: Decodable {
    let id: Int
    let userId: Int
    let externalId: String
    let startTime: Date
    let endTime: Date
    let deepMinutes: Int
    let remMinutes: Int
    let coreMinutes: Int
    let awakeMinutes: Int
    let createdAt: Date
}
