//
//  SleepRepository.swift
//  SnoozeQuest
//

import Foundation

protocol SleepRepository {
    func fetchDailySummaries(days: Int) async throws -> [DailySleepSummary]
    func fetchLatestSummary() async throws -> DailySleepSummary?
}

final class MockSleepRepository: SleepRepository {
    private let summaries: [DailySleepSummary]

    init(summaries: [DailySleepSummary] = MockSleepData.dailySummaries) {
        self.summaries = summaries
    }

    func fetchDailySummaries(days: Int) async throws -> [DailySleepSummary] {
        Array(summaries.suffix(days))
    }

    func fetchLatestSummary() async throws -> DailySleepSummary? {
        summaries.last
    }
}

final class RemoteSleepRepository: SleepRepository {
    private let apiClient: APIClientProtocol
    private let userID: Int
    private let goalRepository: GoalRepository

    init(apiClient: APIClientProtocol, userID: Int, goalRepository: GoalRepository) {
        self.apiClient = apiClient
        self.userID = userID
        self.goalRepository = goalRepository
    }

    func fetchDailySummaries(days: Int) async throws -> [DailySleepSummary] {
        let goal = try await goalRepository.fetchGoal()
        let today = Self.utcCalendar.startOfDay(for: Date())
        let startDate = Self.utcCalendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today

        let endpoint = Endpoint(path: "/api/v1/sleep", queryItems: [
            URLQueryItem(name: "user_id", value: String(userID)),
            URLQueryItem(name: "start_date", value: Self.dateFormatter.string(from: startDate)),
            URLQueryItem(name: "end_date", value: Self.dateFormatter.string(from: today)),
        ])
        let sessions: [SleepSessionDTO] = try await apiClient.request(endpoint)

        return sessions
            .sorted { $0.startTime < $1.startTime }
            .map { Self.makeDailySummary(from: $0, goal: goal) }
    }

    func fetchLatestSummary() async throws -> DailySleepSummary? {
        // A wide lookback, not just "today" — otherwise this incorrectly reports no
        // data whenever the user simply hasn't synced yet today.
        try await fetchDailySummaries(days: 30).last
    }

    private static func makeDailySummary(from dto: SleepSessionDTO, goal: SleepGoal) -> DailySleepSummary {
        let id = UUID(backendID: dto.id)
        let session = SleepSession(
            id: id,
            startDate: dto.startTime,
            endDate: dto.endTime,
            stageDurations: [
                .deep: TimeInterval(dto.deepMinutes * 60),
                .rem: TimeInterval(dto.remMinutes * 60),
                .core: TimeInterval(dto.coreMinutes * 60),
                .awake: TimeInterval(dto.awakeMinutes * 60),
            ]
        )

        let sleepMinutes = dto.deepMinutes + dto.remMinutes + dto.coreMinutes
        let targetMinutes = Int(goal.targetDuration / 60)
        let goalMet = sleepMinutes >= targetMinutes
        let bedtimeDeviation = SleepScoreCalculator.bedtimeDeviationMinutes(
            startDate: dto.startTime, target: goal.bedtime, calendar: utcCalendar
        )
        let score = SleepScoreCalculator.score(
            totalMinutes: sleepMinutes,
            targetMinutes: targetMinutes,
            bedtimeDeviationMinutes: bedtimeDeviation,
            goalMet: goalMet
        )

        return DailySleepSummary(
            id: id,
            date: utcCalendar.startOfDay(for: dto.startTime),
            session: session,
            sleepScore: score,
            goalMet: goalMet
        )
    }

    // The backend stores/compares timestamps in UTC (Postgres `timestamptz`), with no
    // per-user timezone concept, so this mirrors that instead of using the device's
    // local calendar — otherwise bedtime-deviation and day-bucketing would silently
    // shift depending on what timezone this app happens to run in.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
