//
//  HealthKitService.swift
//  SnoozeQuest
//

import Foundation
import HealthKit

enum HealthKitAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

protocol HealthKitServiceProtocol {
    var authorizationStatus: HealthKitAuthorizationStatus { get }
    func requestAuthorization() async -> HealthKitAuthorizationStatus
    func fetchRecentSleepSessions(days: Int) async throws -> [SleepSession]
}

final class HealthKitService: HealthKitServiceProtocol {
    // Samples this close together belong to the same night; a gap this large means
    // the person got up, so the next sample starts a new session.
    private static let sessionMergeGap: TimeInterval = 3600

    private let healthStore = HKHealthStore()
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

    var authorizationStatus: HealthKitAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        switch healthStore.authorizationStatus(for: sleepType) {
        case .notDetermined: return .notDetermined
        case .sharingDenied: return .denied
        case .sharingAuthorized: return .authorized
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization() async -> HealthKitAuthorizationStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
        } catch {
            return .denied
        }
        return authorizationStatus
    }

    func fetchRecentSleepSessions(days: Int) async throws -> [SleepSession] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let samples = try await querySleepSamples(days: days)
        return Self.groupIntoSessions(samples)
    }

    private func querySleepSamples(days: Int) async throws -> [HKCategorySample] {
        let end = Date()
        let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    static func groupIntoSessions(_ samples: [HKCategorySample]) -> [SleepSession] {
        guard !samples.isEmpty else { return [] }
        let sorted = samples.sorted { $0.startDate < $1.startDate }

        var groups: [[HKCategorySample]] = []
        var currentGroup = [sorted[0]]
        for sample in sorted.dropFirst() {
            if let previousEnd = currentGroup.last?.endDate,
               sample.startDate.timeIntervalSince(previousEnd) > sessionMergeGap {
                groups.append(currentGroup)
                currentGroup = [sample]
            } else {
                currentGroup.append(sample)
            }
        }
        groups.append(currentGroup)

        return groups.compactMap(makeSession)
    }

    private static func makeSession(from samples: [HKCategorySample]) -> SleepSession? {
        var stageDurations: [SleepStage: TimeInterval] = [:]
        for sample in samples {
            guard let stage = stage(forRawCategoryValue: sample.value) else { continue }
            stageDurations[stage, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
        }
        guard !stageDurations.isEmpty,
              let startDate = samples.map(\.startDate).min(),
              let endDate = samples.map(\.endDate).max()
        else { return nil }

        return SleepSession(id: UUID(), startDate: startDate, endDate: endDate, stageDurations: stageDurations)
    }

    private static func stage(forRawCategoryValue value: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .awake: return .awake
        case .asleepREM: return .rem
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        default: return nil
        }
    }
}

final class MockHealthKitService: HealthKitServiceProtocol {
    var authorizationStatus: HealthKitAuthorizationStatus

    init(authorizationStatus: HealthKitAuthorizationStatus = .notDetermined) {
        self.authorizationStatus = authorizationStatus
    }

    func requestAuthorization() async -> HealthKitAuthorizationStatus {
        authorizationStatus = .authorized
        return authorizationStatus
    }

    func fetchRecentSleepSessions(days: Int) async throws -> [SleepSession] {
        []
    }
}
