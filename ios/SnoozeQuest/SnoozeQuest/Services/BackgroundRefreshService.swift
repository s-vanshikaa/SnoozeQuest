//
//  BackgroundRefreshService.swift
//  SnoozeQuest
//

import BackgroundTasks
import Foundation

final class BackgroundRefreshService {
    static let taskIdentifier = "com.vanshika.SnoozeQuest.refresh"
    private static let minimumInterval: TimeInterval = 4 * 3600

    private let coordinator: SleepSyncCoordinator

    init(coordinator: SleepSyncCoordinator) {
        self.coordinator = coordinator
    }

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(refreshTask)
        }
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.minimumInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGAppRefreshTask) {
        // The OS decides when (or whether) this actually runs — resubmit right away so the
        // next opportunity stays queued no matter how this run turns out.
        scheduleNextRefresh()

        let work = Task {
            let success = await Self.performRefresh(coordinator: coordinator)
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    static func performRefresh(coordinator: SleepSyncCoordinator) async -> Bool {
        let outcome = await coordinator.refresh()
        return outcome == .synced && !Task.isCancelled
    }
}
