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
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncOutcome: SleepSyncOutcome?

    private let healthKitService: HealthKitServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private let goalRepository: GoalRepository
    private let syncCoordinator: SleepSyncCoordinator?
    private let userDefaults: UserDefaults

    init(
        healthKitService: HealthKitServiceProtocol = MockHealthKitService(),
        notificationService: NotificationServiceProtocol = MockNotificationService(),
        goalRepository: GoalRepository = MockGoalRepository(),
        syncCoordinator: SleepSyncCoordinator? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.healthKitService = healthKitService
        self.notificationService = notificationService
        self.goalRepository = goalRepository
        self.syncCoordinator = syncCoordinator
        self.userDefaults = userDefaults
        self.lastSyncDate = syncCoordinator?.lastSuccessfulSync
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

    var lastSyncText: String {
        guard let lastSyncDate else { return "Never" }
        return lastSyncDate.formatted(date: .abbreviated, time: .shortened)
    }

    var syncStatusMessage: String? {
        switch lastSyncOutcome {
        case .importFailed: return "Couldn't read sleep data from Apple Health."
        case .syncFailed: return "Some nights couldn't be uploaded. They'll retry on the next sync."
        case .synced, nil: return nil
        }
    }

    var canSyncNow: Bool {
        healthKitStatus == .authorized && syncCoordinator != nil && !isSyncing
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
        if healthKitStatus == .authorized {
            await syncNow()
        }
    }

    /// Imports the last week from Apple Health and uploads whatever is pending.
    func syncNow() async {
        guard let syncCoordinator, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        lastSyncOutcome = await syncCoordinator.refresh()
        lastSyncDate = syncCoordinator.lastSuccessfulSync
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
