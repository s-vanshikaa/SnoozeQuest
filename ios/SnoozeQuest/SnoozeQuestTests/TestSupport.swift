//
//  TestSupport.swift
//  SnoozeQuestTests
//

import Foundation
import SwiftData
@testable import SnoozeQuest

func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func makeInMemoryStore() throws -> SwiftDataSleepSessionStore {
    let schema = Schema([SleepSessionRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return SwiftDataSleepSessionStore(context: ModelContext(container))
}
