//
//  GoalRepository.swift
//  SnoozeQuest
//

import Foundation

protocol GoalRepository {
    func fetchGoal() async throws -> SleepGoal
    func saveGoal(_ goal: SleepGoal) async throws
}

actor MockGoalRepository: GoalRepository {
    private var goal: SleepGoal

    init(goal: SleepGoal = MockSleepData.goal) {
        self.goal = goal
    }

    func fetchGoal() async throws -> SleepGoal {
        goal
    }

    func saveGoal(_ goal: SleepGoal) async throws {
        self.goal = goal
    }
}
