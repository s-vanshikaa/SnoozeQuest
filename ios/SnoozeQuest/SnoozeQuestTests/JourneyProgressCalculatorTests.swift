//
//  JourneyProgressCalculatorTests.swift
//  SnoozeQuestTests
//

import Testing
@testable import SnoozeQuest

struct JourneyProgressCalculatorTests {
    @Test func zeroGoalNightsStartsOnEarthAsCurrent() {
        let result = JourneyProgressCalculator.compute(goalNightsCompleted: 0)

        #expect(result.currentWorld.name == "Earth")
        #expect(result.currentWorld.state == .current)
        #expect(result.worlds.dropFirst().allSatisfy { $0.state == .locked })
    }

    @Test func goalNightsBetweenThresholdsUnlocksPriorWorlds() {
        // Mars requires 4, Venus requires 9 -> 5 nights means Earth unlocked, Mars current, rest locked.
        let result = JourneyProgressCalculator.compute(goalNightsCompleted: 5)

        #expect(result.currentWorld.name == "Mars")
        #expect(result.worlds[0].state == .unlocked)
        #expect(result.worlds[1].state == .current)
        #expect(result.worlds[2].state == .locked)
        #expect(result.goalNightsUntilNext == 4)
        #expect(result.nextWorldName == "Venus")
    }

    @Test func progressToNextWorldIsFractionOfSpan() {
        // Mars=4, Venus=9, span=5. At 6 nights, 2/5 of the way = 0.4.
        let result = JourneyProgressCalculator.compute(goalNightsCompleted: 6)
        #expect(abs(result.progressToNextWorld - 0.4) < 0.0001)
    }

    @Test func reachingFinalWorldReportsNoNextWorld() {
        let result = JourneyProgressCalculator.compute(goalNightsCompleted: 30)

        #expect(result.currentWorld.name == "Neptune")
        #expect(result.goalNightsUntilNext == nil)
        #expect(result.nextWorldName == nil)
        #expect(result.progressToNextWorld == 1.0)
    }
}
