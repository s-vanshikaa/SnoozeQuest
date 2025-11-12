//
//  NotificationServiceTests.swift
//  SnoozeQuestTests
//

import Testing
@testable import SnoozeQuest

struct NotificationServiceTests {
    @Test func timeBeforeSubtractsTheLeadTime() {
        let result = NotificationService.time(before: TimeOfDay(hour: 23, minute: 0), by: 30 * 60)

        #expect(result == TimeOfDay(hour: 22, minute: 30))
    }

    @Test func timeBeforeWrapsBackwardAcrossMidnight() {
        let result = NotificationService.time(before: TimeOfDay(hour: 0, minute: 15), by: 30 * 60)

        #expect(result == TimeOfDay(hour: 23, minute: 45))
    }
}
