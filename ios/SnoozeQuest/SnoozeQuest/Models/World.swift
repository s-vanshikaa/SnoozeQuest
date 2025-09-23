//
//  World.swift
//  SnoozeQuest
//

import Foundation

enum WorldState: Equatable {
    case unlocked
    case current
    case locked
}

struct World: Identifiable, Equatable {
    let id: Int
    let name: String
    /// Cumulative goal-met nights required to reach this world.
    let requiredGoalNights: Int
}

extension World {
    /// Reference catalog of worlds in journey order. Thresholds are cumulative
    /// counts of goal-met nights, tuned for SnoozeQuest's ~30-day mock dataset.
    static let catalog: [World] = [
        World(id: 0, name: "Earth", requiredGoalNights: 0),
        World(id: 1, name: "Mars", requiredGoalNights: 4),
        World(id: 2, name: "Venus", requiredGoalNights: 9),
        World(id: 3, name: "Saturn", requiredGoalNights: 15),
        World(id: 4, name: "Jupiter", requiredGoalNights: 22),
        World(id: 5, name: "Neptune", requiredGoalNights: 30)
    ]
}
