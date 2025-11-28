//
//  SleepSyncCoordinator.swift
//  SnoozeQuest
//
//  HealthKit -> SwiftData -> SyncEngine. Every entry point (connecting Apple Health,
//  Sync Now, background refresh) goes through `refresh()` so they behave identically.
//

import Foundation

extension Notification.Name {
    /// Posted after a refresh finishes uploading, so screens showing backend data can reload.
    static let sleepDataDidSync = Notification.Name("sleepDataDidSync")
}

enum SleepSyncOutcome: Equatable {
    /// Import and upload both finished. Includes the case where HealthKit had nothing new.
    case synced
    case importFailed
    /// Upload didn't finish; the affected records stay pending and are retried next time.
    case syncFailed
}

final class SleepSyncCoordinator {
    static let importLookbackDays = 7
    static let lastSuccessfulSyncKey = "lastSuccessfulSyncDate"

    private let healthKitImportService: HealthKitImportService
    private let syncEngine: SyncEngine
    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private var inFlight: Task<SleepSyncOutcome, Never>?

    init(
        healthKitImportService: HealthKitImportService,
        syncEngine: SyncEngine,
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.healthKitImportService = healthKitImportService
        self.syncEngine = syncEngine
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
        self.now = now
    }

    var lastSuccessfulSync: Date? {
        userDefaults.object(forKey: Self.lastSuccessfulSyncKey) as? Date
    }

    /// Imports the last week of sleep, then uploads everything still pending.
    /// Overlapping calls share one run instead of touching the store concurrently.
    func refresh() async -> SleepSyncOutcome {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { await performRefresh() }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        return outcome
    }

    private func performRefresh() async -> SleepSyncOutcome {
        do {
            try await healthKitImportService.importRecentSleep(days: Self.importLookbackDays)
        } catch {
            return .importFailed
        }

        let outcome: SleepSyncOutcome
        do {
            let summary = try await syncEngine.sync()
            outcome = summary.failed == 0 ? .synced : .syncFailed
        } catch {
            outcome = .syncFailed
        }

        if outcome == .synced {
            userDefaults.set(now(), forKey: Self.lastSuccessfulSyncKey)
        }
        // Even a partial upload changed what the backend knows, so screens should reload.
        notificationCenter.post(name: .sleepDataDidSync, object: nil)
        return outcome
    }
}
