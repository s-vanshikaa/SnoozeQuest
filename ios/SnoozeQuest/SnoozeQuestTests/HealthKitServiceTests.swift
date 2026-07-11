//
//  HealthKitServiceTests.swift
//  SnoozeQuestTests
//

import Foundation
import HealthKit
import Testing
@testable import SnoozeQuest

struct HealthKitServiceTests {
    private static let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

    private static func sample(_ value: HKCategoryValueSleepAnalysis, _ start: Date, _ end: Date) -> HKCategorySample {
        HKCategorySample(type: sleepType, value: value.rawValue, start: start, end: end)
    }

    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func date(_ hoursFromReference: Double) -> Date {
        referenceDate.addingTimeInterval(hoursFromReference * 3600)
    }

    @Test func groupsContiguousSamplesIntoOneSessionWithSummedStageDurations() {
        let samples = [
            Self.sample(.asleepCore, Self.date(0), Self.date(1)),
            Self.sample(.asleepDeep, Self.date(1), Self.date(1.5)),
            Self.sample(.asleepREM, Self.date(1.5), Self.date(2)),
            Self.sample(.awake, Self.date(2), Self.date(2.1)),
        ]

        let sessions = HealthKitService.groupIntoSessions(samples)

        #expect(sessions.count == 1)
        let session = sessions[0]
        #expect(session.stageDurations[.core] == 3600)
        #expect(session.stageDurations[.deep] == 1800)
        #expect(session.stageDurations[.rem] == 1800)
        #expect(session.stageDurations[.awake] == 360)
        #expect(session.startDate == Self.date(0))
        #expect(session.endDate == Self.date(2.1))
    }

    @Test func splitsSamplesSeparatedByALargeGapIntoDistinctSessions() {
        let samples = [
            Self.sample(.asleepCore, Self.date(-30), Self.date(-29)),
            Self.sample(.asleepCore, Self.date(0), Self.date(1)),
        ]

        let sessions = HealthKitService.groupIntoSessions(samples)

        #expect(sessions.count == 2)
    }

    @Test func ignoresInBedSamplesWhenComputingStageDurations() {
        let samples = [
            Self.sample(.inBed, Self.date(0), Self.date(0.2)),
            Self.sample(.asleepCore, Self.date(0.2), Self.date(1)),
        ]

        let sessions = HealthKitService.groupIntoSessions(samples)

        #expect(sessions.count == 1)
        #expect(sessions[0].stageDurations[.core] == 2880)
        #expect(sessions[0].stageDurations.count == 1)
    }

    @Test func aClusterOfOnlyInBedSamplesProducesNoSession() {
        let samples = [Self.sample(.inBed, Self.date(0), Self.date(1))]

        let sessions = HealthKitService.groupIntoSessions(samples)

        #expect(sessions.isEmpty)
    }
}
