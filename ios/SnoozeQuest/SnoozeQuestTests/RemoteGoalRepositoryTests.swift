//
//  RemoteGoalRepositoryTests.swift
//  SnoozeQuestTests
//

import Foundation
import Testing
@testable import SnoozeQuest

struct RemoteGoalRepositoryTests {
    @Test func fetchGoalMapsDTOToDomainModel() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/goals/current", value: GoalDTO(
            id: 1, userId: 1, targetMinutes: 480, targetBedtime: "23:00:00", targetWakeTime: "07:00:00", updatedAt: Date()
        ))
        let repository = RemoteGoalRepository(apiClient: client, userID: 1)

        let goal = try await repository.fetchGoal()

        #expect(goal.targetDuration == 480 * 60)
        #expect(goal.bedtime == TimeOfDay(hour: 23, minute: 0))
        #expect(goal.wakeTime == TimeOfDay(hour: 7, minute: 0))
    }

    @Test func fetchGoalIncludesUserIDQueryItem() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/goals/current", value: GoalDTO(
            id: 1, userId: 42, targetMinutes: 480, targetBedtime: "23:00:00", targetWakeTime: "07:00:00", updatedAt: Date()
        ))
        let repository = RemoteGoalRepository(apiClient: client, userID: 42)

        _ = try await repository.fetchGoal()

        #expect(client.requestedEndpoints.first?.queryItems.contains(URLQueryItem(name: "user_id", value: "42")) == true)
    }

    @Test func saveGoalSendsCorrectPUTPayload() async throws {
        let client = FakeAPIClient()
        client.stub(path: "/api/v1/goals/current", value: GoalDTO(
            id: 1, userId: 1, targetMinutes: 450, targetBedtime: "22:30:00", targetWakeTime: "06:30:00", updatedAt: Date()
        ))
        let repository = RemoteGoalRepository(apiClient: client, userID: 1)

        try await repository.saveGoal(SleepGoal(
            targetDuration: 450 * 60,
            bedtime: TimeOfDay(hour: 22, minute: 30),
            wakeTime: TimeOfDay(hour: 6, minute: 30)
        ))

        let request = client.requestedEndpoints.first
        #expect(request?.method == .put)

        let body = try #require(request?.body)
        let decoded = try APIClient.makeDecoder().decode(GoalUpdateDTO.self, from: body)
        #expect(decoded.userId == 1)
        #expect(decoded.targetMinutes == 450)
        #expect(decoded.targetBedtime == "22:30:00")
        #expect(decoded.targetWakeTime == "06:30:00")
    }
}
