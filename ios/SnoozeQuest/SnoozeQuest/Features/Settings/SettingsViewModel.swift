//
//  SettingsViewModel.swift
//  SnoozeQuest
//

import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var healthKitStatus: HealthKitAuthorizationStatus

    private let healthKitService: HealthKitServiceProtocol

    init(healthKitService: HealthKitServiceProtocol = MockHealthKitService()) {
        self.healthKitService = healthKitService
        self.healthKitStatus = healthKitService.authorizationStatus
    }

    var healthKitStatusText: String {
        switch healthKitStatus {
        case .notDetermined: return "Not Connected"
        case .authorized: return "Connected"
        case .denied: return "Access Denied"
        case .unavailable: return "Not Available"
        }
    }

    func connectAppleHealth() async {
        healthKitStatus = await healthKitService.requestAuthorization()
    }
}
