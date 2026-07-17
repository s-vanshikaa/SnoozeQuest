//
//  SettingsViewModel.swift
//  SnoozeQuest
//

import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    private static let bedtimeReminderEnabledKey = "bedtimeReminderEnabled"
    private static let weeklySummaryReminderEnabledKey = "weeklySummaryReminderEnabled"

    @Published private(set) var healthKitStatus: HealthKitAuthorizationStatus
    @Published private(set) var notificationStatus: NotificationAuthorizationStatus = .notDetermined
    @Published var bedtimeReminderEnabled: Bool
    @Published var weeklySummaryReminderEnabled: Bool

    private let healthKitService: HealthKitServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let goalRepository: GoalRepository
    private let userDefaults: UserDefaults

    init(
        healthKitService: HealthKitServiceProtocol = MockHealthKitService(),
        notificationService: NotificationServiceProtocol = MockNotificationService(),
        goalRepository: GoalRepository = MockGoalRepository(),
        userDefaults: UserDefaults = .standard
    ) {
        self.healthKitService = healthKitService
        self.notificationService = notificationService
        self.goalRepository = goalRepository
        self.userDefaults = userDefaults
        self.healthKitStatus = healthKitService.authorizationStatus
        self.bedtimeReminderEnabled = userDefaults.bool(forKey: Self.bedtimeReminderEnabledKey)
        self.weeklySummaryReminderEnabled = userDefaults.bool(forKey: Self.weeklySummaryReminderEnabledKey)
    }

    var healthKitStatusText: String {
        switch healthKitStatus {
        case .notDetermined: return "Not Connected"
        case .authorized: return "Connected"
        case .denied: return "Access Denied"
        case .unavailable: return "Not Available"
        }
    }

    var notificationStatusText: String {
        switch notificationStatus {
        case .notDetermined: return "Not Enabled"
        case .authorized: return "Enabled"
        case .denied: return "Access Denied"
        }
    }

    func load() async {
        notificationStatus = await notificationService.authorizationStatus()
    }

    func connectAppleHealth() async {
        healthKitStatus = await healthKitService.requestAuthorization()
    }

    func requestNotificationAuthorization() async {
        notificationStatus = await notificationService.requestAuthorization()
    }

    func setBedtimeReminderEnabled(_ enabled: Bool) async {
        userDefaults.set(enabled, forKey: Self.bedtimeReminderEnabledKey)
        if enabled {
            guard let goal = try? await goalRepository.fetchGoal() else { return }
            try? await notificationService.scheduleBedtimeReminder(bedtime: goal.bedtime)
        } else {
            await notificationService.cancelBedtimeReminder()
        }
    }

    func setWeeklySummaryReminderEnabled(_ enabled: Bool) async {
        userDefaults.set(enabled, forKey: Self.weeklySummaryReminderEnabledKey)
        if enabled {
            try? await notificationService.scheduleWeeklySummaryReminder()
        } else {
            await notificationService.cancelWeeklySummaryReminder()
        }
    }
}
