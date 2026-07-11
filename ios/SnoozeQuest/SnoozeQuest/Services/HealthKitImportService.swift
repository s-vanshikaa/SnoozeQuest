//
//  HealthKitImportService.swift
//  SnoozeQuest
//

import Foundation

final class HealthKitImportService {
    private let healthKitService: HealthKitServiceProtocol
    private let sleepSessionStore: SleepSessionStore

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    init(healthKitService: HealthKitServiceProtocol, sleepSessionStore: SleepSessionStore) {
        self.healthKitService = healthKitService
        self.sleepSessionStore = sleepSessionStore
    }

    func importRecentSleep(days: Int) async throws {
        let sessions = try await healthKitService.fetchRecentSleepSessions(days: days)
        for session in sessions {
            try sleepSessionStore.save(
                externalID: "healthkit-\(Self.dayFormatter.string(from: session.startDate))",
                startDate: session.startDate,
                endDate: session.endDate,
                deepMinutes: minutes(session, .deep),
                remMinutes: minutes(session, .rem),
                coreMinutes: minutes(session, .core),
                awakeMinutes: minutes(session, .awake)
            )
        }
    }

    private func minutes(_ session: SleepSession, _ stage: SleepStage) -> Int {
        Int((session.stageDurations[stage] ?? 0) / 60)
    }
}
