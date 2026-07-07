//
//  SwiftDataSleepSessionStoreTests.swift
//  SnoozeQuestTests
//

import Foundation
import SwiftData
import Testing
@testable import SnoozeQuest

struct SwiftDataSleepSessionStoreTests {
    private static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func makeInMemoryStore() throws -> SwiftDataSleepSessionStore {
        let schema = Schema([SleepSessionRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return SwiftDataSleepSessionStore(context: ModelContext(container))
    }

    @Test func saveInsertsNewRecordAsPending() throws {
        let store = try Self.makeInMemoryStore()
        let start = Self.utcDate(2026, 1, 1, 23, 0)

        try store.save(
            externalID: "healthkit-1", startDate: start, endDate: start.addingTimeInterval(8 * 3600),
            deepMinutes: 90, remMinutes: 100, coreMinutes: 270, awakeMinutes: 20
        )

        let records = try store.fetchAll()
        #expect(records.count == 1)
        #expect(records[0].externalID == "healthkit-1")
        #expect(records[0].syncState == .pending)
    }

    @Test func saveWithDuplicateExternalIDUpdatesExistingRecordInstead() throws {
        let store = try Self.makeInMemoryStore()
        let start = Self.utcDate(2026, 1, 1, 23, 0)

        try store.save(
            externalID: "healthkit-1", startDate: start, endDate: start.addingTimeInterval(7 * 3600),
            deepMinutes: 80, remMinutes: 90, coreMinutes: 230, awakeMinutes: 20
        )
        try store.save(
            externalID: "healthkit-1", startDate: start, endDate: start.addingTimeInterval(8 * 3600),
            deepMinutes: 90, remMinutes: 100, coreMinutes: 270, awakeMinutes: 20
        )

        let records = try store.fetchAll()
        #expect(records.count == 1)
        #expect(records[0].deepMinutes == 90)
    }

    @Test func fetchUnsyncedExcludesSyncedRecords() throws {
        let store = try Self.makeInMemoryStore()
        let start = Self.utcDate(2026, 1, 1, 23, 0)

        try store.save(
            externalID: "synced", startDate: start, endDate: start.addingTimeInterval(3600),
            deepMinutes: 10, remMinutes: 10, coreMinutes: 10, awakeMinutes: 10
        )
        try store.save(
            externalID: "pending", startDate: start, endDate: start.addingTimeInterval(3600),
            deepMinutes: 10, remMinutes: 10, coreMinutes: 10, awakeMinutes: 10
        )
        try store.updateSyncState(externalID: "synced", to: .synced)

        let unsynced = try store.fetchUnsynced()

        #expect(unsynced.count == 1)
        #expect(unsynced[0].externalID == "pending")
    }

    @Test func updateSyncStateTransitionsRecordToFailed() throws {
        let store = try Self.makeInMemoryStore()
        let start = Self.utcDate(2026, 1, 1, 23, 0)
        try store.save(
            externalID: "healthkit-1", startDate: start, endDate: start.addingTimeInterval(3600),
            deepMinutes: 10, remMinutes: 10, coreMinutes: 10, awakeMinutes: 10
        )

        try store.updateSyncState(externalID: "healthkit-1", to: .failed)

        let records = try store.fetchAll()
        #expect(records[0].syncState == .failed)
    }

    @Test func dataSurvivesAFreshContainerAtTheSameStoreURL() throws {
        let schema = Schema([SleepSessionRecord.self])
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDataSleepSessionStoreTests-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
        }
        let start = Self.utcDate(2026, 1, 1, 23, 0)

        let firstContainer = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        try SwiftDataSleepSessionStore(context: ModelContext(firstContainer)).save(
            externalID: "healthkit-1", startDate: start, endDate: start.addingTimeInterval(3600),
            deepMinutes: 10, remMinutes: 10, coreMinutes: 10, awakeMinutes: 10
        )

        // A new container at the same URL stands in for the app relaunching.
        let secondContainer = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let records = try SwiftDataSleepSessionStore(context: ModelContext(secondContainer)).fetchAll()

        #expect(records.count == 1)
        #expect(records[0].externalID == "healthkit-1")
    }
}
