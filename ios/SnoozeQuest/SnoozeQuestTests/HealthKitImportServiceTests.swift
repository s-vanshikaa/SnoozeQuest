//
//  HealthKitImportServiceTests.swift
//  SnoozeQuestTests
//

import Foundation
import SwiftData
import Testing
@testable import SnoozeQuest

struct HealthKitImportServiceTests {
    private static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func makeStore() throws -> SwiftDataSleepSessionStore {
        let schema = Schema([SleepSessionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return SwiftDataSleepSessionStore(context: ModelContext(container))
    }

    @Test func importRecentSleepSavesNormalizedSessionsToTheStore() async throws {
        let start = Self.utcDate(2026, 1, 1, 23, 0)
        let session = SleepSession(
            id: UUID(), startDate: start, endDate: start.addingTimeInterval(8 * 3600),
            stageDurations: [.deep: 5400, .rem: 3600, .core: 18000, .awake: 300]
        )
        let store = try Self.makeStore()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(
                authorizationStatus: .authorized, statusAfterRequest: .authorized, sessionsToReturn: [session]
            ),
            sleepSessionStore: store
        )

        try await importer.importRecentSleep(days: 7)

        let records = try store.fetchAll()
        #expect(records.count == 1)
        #expect(records[0].deepMinutes == 90)
        #expect(records[0].remMinutes == 60)
        #expect(records[0].coreMinutes == 300)
        #expect(records[0].awakeMinutes == 5)
        #expect(records[0].syncState == .pending)
    }

    @Test func repeatedImportOfTheSameNightDoesNotCreateDuplicateRecords() async throws {
        let start = Self.utcDate(2026, 1, 1, 23, 0)
        let session = SleepSession(
            id: UUID(), startDate: start, endDate: start.addingTimeInterval(8 * 3600),
            stageDurations: [.core: 28800]
        )
        let store = try Self.makeStore()
        let importer = HealthKitImportService(
            healthKitService: FakeHealthKitService(
                authorizationStatus: .authorized, statusAfterRequest: .authorized, sessionsToReturn: [session]
            ),
            sleepSessionStore: store
        )

        try await importer.importRecentSleep(days: 7)
        try await importer.importRecentSleep(days: 7)

        let records = try store.fetchAll()
        #expect(records.count == 1)
    }
}
