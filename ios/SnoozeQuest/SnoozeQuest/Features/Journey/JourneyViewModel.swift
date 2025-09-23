//
//  JourneyViewModel.swift
//  SnoozeQuest
//
//  Journey progress is derived from real (mock) sleep-consistency data — the
//  number of goal-met nights — rather than a disconnected mock dataset. This
//  keeps the seam clean for a future backend-computed implementation.
//

import Combine
import Foundation

struct WorldDisplay: Identifiable, Equatable {
    let id: Int
    let name: String
    let state: WorldState
    let requiredGoalNights: Int
}

struct WorldMilestoneDetail: Equatable {
    let world: WorldDisplay
    let unlockedAfterText: String
    let averageScoreText: String
    let longestStreakText: String
}

typealias JourneyDisplayModel = JourneyProgressResult

@MainActor
final class JourneyViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(JourneyDisplayModel)
        case error(String)
    }

    @Published private(set) var state: State = .loading

    private let sleepRepository: SleepRepository
    private let analyticsRepository: AnalyticsRepository
    private var lastSummaries: [DailySleepSummary] = []
    private var lastAnalytics: SleepAnalytics?

    init(
        sleepRepository: SleepRepository = MockSleepRepository(),
        analyticsRepository: AnalyticsRepository = MockAnalyticsRepository()
    ) {
        self.sleepRepository = sleepRepository
        self.analyticsRepository = analyticsRepository
    }

    func load() async {
        state = .loading
        do {
            async let summaries = sleepRepository.fetchDailySummaries(days: 30)
            async let analytics = analyticsRepository.fetchAnalytics()
            let (fetchedSummaries, fetchedAnalytics) = try await (summaries, analytics)

            lastSummaries = fetchedSummaries
            lastAnalytics = fetchedAnalytics

            let goalNightsCompleted = fetchedSummaries.filter(\.goalMet).count
            state = .loaded(JourneyProgressCalculator.compute(goalNightsCompleted: goalNightsCompleted))
        } catch {
            state = .error("We couldn't load your journey. Pull to refresh to try again.")
        }
    }

    func milestoneDetail(for world: WorldDisplay) -> WorldMilestoneDetail {
        let averageScore = lastAnalytics?.averageSleepScore ?? 0
        let longestStreak = Self.longestStreak(in: lastSummaries)

        return WorldMilestoneDetail(
            world: world,
            unlockedAfterText: world.requiredGoalNights == 0
                ? "Your starting world"
                : "Unlocked after \(world.requiredGoalNights) goal nights",
            averageScoreText: "\(averageScore)",
            longestStreakText: "\(longestStreak) night\(longestStreak == 1 ? "" : "s")"
        )
    }

    private static func longestStreak(in summaries: [DailySleepSummary]) -> Int {
        var longest = 0
        var current = 0
        for summary in summaries.sorted(by: { $0.date < $1.date }) {
            if summary.goalMet {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    convenience init(previewState: State) {
        self.init()
        state = previewState
    }
}
