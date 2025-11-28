//
//  OnboardingViewModelTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

@MainActor
struct OnboardingViewModelTests {
    private static let existingGoal = SleepGoal(
        targetDuration: 8 * 3600, bedtime: TimeOfDay(hour: 23, minute: 0), wakeTime: TimeOfDay(hour: 7, minute: 0)
    )

    @Test func confirmGoalSavesTheSelectedDurationThroughTheGoalRepository() async {
        let repository = FakeGoalRepository(goal: Self.existingGoal)
        let viewModel = OnboardingViewModel(goalRepository: repository, onFinish: {})
        viewModel.targetDuration = 7 * 3600

        await viewModel.confirmGoal()

        let saved = await repository.savedGoals
        #expect(saved.count == 1)
        #expect(saved[0].targetDuration == 7 * 3600)
        #expect(viewModel.step == .completion)
    }

    @Test func confirmGoalKeepsTheExistingBedtimeAndWakeTime() async {
        let repository = FakeGoalRepository(goal: Self.existingGoal)
        let viewModel = OnboardingViewModel(goalRepository: repository, onFinish: {})
        viewModel.targetDuration = 9 * 3600

        await viewModel.confirmGoal()

        let saved = await repository.savedGoals
        #expect(saved[0].bedtime == TimeOfDay(hour: 23, minute: 0))
        #expect(saved[0].wakeTime == TimeOfDay(hour: 7, minute: 0))
    }

    @Test func confirmGoalReachesTheBackendAsAGoalUpdate() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/goals/current", value: GoalDTO(
            id: 1, userId: 1, targetMinutes: 480, targetBedtime: "23:00:00", targetWakeTime: "07:00:00", updatedAt: Date()
        ))
        let viewModel = OnboardingViewModel(
            goalRepository: RemoteGoalRepository(apiClient: client, userID: 1), onFinish: {}
        )
        viewModel.targetDuration = 7.5 * 3600

        await viewModel.confirmGoal()

        let put = try #require(client.requestedEndpoints.first { $0.method == .put })
        let body = try #require(put.body)
        let decoded = try APIClient.makeDecoder().decode(GoalUpdateDTO.self, from: body)
        #expect(decoded.targetMinutes == 450)
        #expect(decoded.targetBedtime == "23:00:00")
    }
}
