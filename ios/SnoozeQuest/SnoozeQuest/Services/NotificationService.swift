//
//  NotificationService.swift
//  SnoozeQuest
//

import Foundation
import UserNotifications

enum NotificationAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied
}

protocol NotificationServiceProtocol {
    func authorizationStatus() async -> NotificationAuthorizationStatus
    func requestAuthorization() async -> NotificationAuthorizationStatus
    func scheduleBedtimeReminder(bedtime: TimeOfDay) async throws
    func cancelBedtimeReminder() async
    func scheduleWeeklySummaryReminder() async throws
    func cancelWeeklySummaryReminder() async
}

final class NotificationService: NotificationServiceProtocol {
    private static let bedtimeReminderID = "bedtime-reminder"
    private static let weeklySummaryReminderID = "weekly-summary-reminder"
    private static let bedtimeLeadTime: TimeInterval = 30 * 60

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization() async -> NotificationAuthorizationStatus {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return .denied
        }
        return await authorizationStatus()
    }

    func scheduleBedtimeReminder(bedtime: TimeOfDay) async throws {
        let reminderTime = Self.time(before: bedtime, by: Self.bedtimeLeadTime)

        let content = UNMutableNotificationContent()
        content.title = "Time to wind down"
        content.body = "Your bedtime is in 30 minutes — start settling in for a good night's sleep."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = reminderTime.hour
        dateComponents.minute = reminderTime.minute

        let request = UNNotificationRequest(
            identifier: Self.bedtimeReminderID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        )
        try await center.add(request)
    }

    func cancelBedtimeReminder() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.bedtimeReminderID])
    }

    func scheduleWeeklySummaryReminder() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Your weekly sleep summary is ready"
        content.body = "See how your week went and what's next on your journey."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 18
        dateComponents.minute = 0

        let request = UNNotificationRequest(
            identifier: Self.weeklySummaryReminderID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        )
        try await center.add(request)
    }

    func cancelWeeklySummaryReminder() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.weeklySummaryReminderID])
    }

    // Subtracting a lead time can cross midnight into the previous day, so this wraps
    // within a 24-hour clock rather than just subtracting minutes directly.
    static func time(before time: TimeOfDay, by leadTime: TimeInterval) -> TimeOfDay {
        let minutesPerDay = 24 * 60
        let totalMinutes = time.hour * 60 + time.minute
        let leadMinutes = Int(leadTime / 60)
        let adjustedMinutes = (totalMinutes - leadMinutes + minutesPerDay) % minutesPerDay
        return TimeOfDay(hour: adjustedMinutes / 60, minute: adjustedMinutes % 60)
    }
}

final class MockNotificationService: NotificationServiceProtocol {
    var status: NotificationAuthorizationStatus

    init(status: NotificationAuthorizationStatus = .notDetermined) {
        self.status = status
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async -> NotificationAuthorizationStatus {
        status = .authorized
        return status
    }

    func scheduleBedtimeReminder(bedtime: TimeOfDay) async throws {}

    func cancelBedtimeReminder() async {}

    func scheduleWeeklySummaryReminder() async throws {}

    func cancelWeeklySummaryReminder() async {}
}
