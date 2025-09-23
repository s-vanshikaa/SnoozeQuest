//
//  JourneyProgressCalculator.swift
//  SnoozeQuest
//
//  Pure, deterministic Journey progress logic shared by JourneyViewModel and
//  GoalsViewModel — isolated from UI code and independently testable, the same
//  way the sleep-score calculation is expected to stay isolated (PRD §10).
//

import Foundation

struct JourneyProgressResult: Equatable {
    let worlds: [WorldDisplay]
    let currentWorldIndex: Int
    let goalNightsCompleted: Int
    let goalNightsUntilNext: Int?
    let progressToNextWorld: Double
    let nextWorldName: String?

    var currentWorld: WorldDisplay { worlds[currentWorldIndex] }
}

enum JourneyProgressCalculator {
    static func compute(goalNightsCompleted: Int, catalog: [World] = World.catalog) -> JourneyProgressResult {
        var currentIndex = 0
        for (index, world) in catalog.enumerated() where goalNightsCompleted >= world.requiredGoalNights {
            currentIndex = index
        }

        let worlds = catalog.enumerated().map { index, world in
            WorldDisplay(
                id: world.id,
                name: world.name,
                state: index < currentIndex ? .unlocked : (index == currentIndex ? .current : .locked),
                requiredGoalNights: world.requiredGoalNights
            )
        }

        let nextIndex = currentIndex + 1
        var goalNightsUntilNext: Int?
        var nextWorldName: String?
        var progress = 1.0

        if nextIndex < catalog.count {
            let next = catalog[nextIndex]
            let current = catalog[currentIndex]
            goalNightsUntilNext = max(next.requiredGoalNights - goalNightsCompleted, 0)
            nextWorldName = next.name

            let span = Double(next.requiredGoalNights - current.requiredGoalNights)
            let progressed = Double(goalNightsCompleted - current.requiredGoalNights)
            progress = span > 0 ? min(max(progressed / span, 0), 1) : 1
        }

        return JourneyProgressResult(
            worlds: worlds,
            currentWorldIndex: currentIndex,
            goalNightsCompleted: goalNightsCompleted,
            goalNightsUntilNext: goalNightsUntilNext,
            progressToNextWorld: progress,
            nextWorldName: nextWorldName
        )
    }
}
