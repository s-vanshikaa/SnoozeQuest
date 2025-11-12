//
//  SnoozeQuestApp.swift
//  SnoozeQuest
//
//  Created by Vanshika Saini on 15/8/26.
//

import SwiftUI

@main
struct SnoozeQuestApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppEnvironment.backgroundRefreshService.register()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                AppEnvironment.backgroundRefreshService.scheduleNextRefresh()
            }
        }
    }
}
