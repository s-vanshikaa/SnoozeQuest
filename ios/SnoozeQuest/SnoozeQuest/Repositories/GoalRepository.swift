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

final class RemoteGoalRepository: GoalRepository {
    private let apiClient: APIClientProtocol
    private let userID: Int

    init(apiClient: APIClientProtocol, userID: Int) {
        self.apiClient = apiClient
        self.userID = userID
    }

    func fetchGoal() async throws -> SleepGoal {
        let endpoint = Endpoint(path: "/api/v1/goals/current", queryItems: [
            URLQueryItem(name: "user_id", value: String(userID)),
        ])
        let dto: GoalDTO = try await apiClient.request(endpoint)
        return Self.makeSleepGoal(from: dto)
    }

    func saveGoal(_ goal: SleepGoal) async throws {
        let payload = GoalUpdateDTO(
            userId: userID,
            targetMinutes: Int(goal.targetDuration / 60),
            targetBedtime: Self.timeString(from: goal.bedtime),
            targetWakeTime: Self.timeString(from: goal.wakeTime)
        )
        let body = try APIClient.makeEncoder().encode(payload)
        let endpoint = Endpoint(path: "/api/v1/goals/current", method: .put, body: body)
        let _: GoalDTO = try await apiClient.request(endpoint)
    }

    private static func makeSleepGoal(from dto: GoalDTO) -> SleepGoal {
        SleepGoal(
            targetDuration: TimeInterval(dto.targetMinutes * 60),
            bedtime: parseTime(dto.targetBedtime),
            wakeTime: parseTime(dto.targetWakeTime)
        )
    }

    private static func parseTime(_ value: String) -> TimeOfDay {
        let components = value.split(separator: ":")
        let hour = components.count > 0 ? Int(components[0]) ?? 0 : 0
        let minute = components.count > 1 ? Int(components[1]) ?? 0 : 0
        return TimeOfDay(hour: hour, minute: minute)
    }

    private static func timeString(from time: TimeOfDay) -> String {
        String(format: "%02d:%02d:00", time.hour, time.minute)
    }
}
