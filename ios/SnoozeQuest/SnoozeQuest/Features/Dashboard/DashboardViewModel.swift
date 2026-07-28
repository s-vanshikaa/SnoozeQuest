//
//  DashboardViewModel.swift
//  SnoozeQuest
//

import Combine
import Foundation

struct DashboardDisplayModel: Equatable {
    struct StageBreakdown: Identifiable, Equatable {
        let id: SleepStage
        let stage: SleepStage
        let percentage: Double
    }

    struct TrendPoint: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let sleepScore: Int
    }

    let greeting: String
    let dateText: String
    let sleepScore: Int
    let latestDurationText: String
    let durationDeltaText: String?
    let goalProgress: Double
    let goalProgressText: String
    let stageBreakdown: [StageBreakdown]
    let sevenDayTrend: [TrendPoint]
}

@MainActor
final class DashboardViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(DashboardDisplayModel)
        case empty
        case error(String)
    }

    @Published private(set) var state: State = .loading

    private let sleepRepository: SleepRepository
    private let goalRepository: GoalRepository
    private let analyticsRepository: AnalyticsRepository

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()

    init(
        sleepRepository: SleepRepository = MockSleepRepository(),
        goalRepository: GoalRepository = MockGoalRepository(),
        analyticsRepository: AnalyticsRepository = MockAnalyticsRepository()
    ) {
        self.sleepRepository = sleepRepository
        self.goalRepository = goalRepository
        self.analyticsRepository = analyticsRepository
    }

    func load() async {
        state = .loading
        do {
            async let latestSummary = sleepRepository.fetchLatestSummary()
            async let goal = goalRepository.fetchGoal()
            async let analytics = analyticsRepository.fetchAnalytics()

            let (summary, fetchedGoal, fetchedAnalytics) = try await (latestSummary, goal, analytics)

            guard let summary else {
                state = .empty
                return
            }

            state = .loaded(Self.makeDisplayModel(summary: summary, goal: fetchedGoal, analytics: fetchedAnalytics))
        } catch {
            state = .error("We couldn't load your sleep data. Pull to refresh to try again.")
        }
    }

    private static func makeDisplayModel(
        summary: DailySleepSummary,
        goal: SleepGoal,
        analytics: SleepAnalytics
    ) -> DashboardDisplayModel {
        let duration = summary.session.duration
        let stageTotal = summary.session.stageDurations.values.reduce(0, +)

        let stageBreakdown = SleepStage.allCases.map { stage -> DashboardDisplayModel.StageBreakdown in
            let stageDuration = summary.session.stageDurations[stage] ?? 0
            let percentage = stageTotal > 0 ? stageDuration / stageTotal : 0
            return DashboardDisplayModel.StageBreakdown(id: stage, stage: stage, percentage: percentage)
        }

        let sevenDayTrend = analytics.sevenDayTrend.map { daySummary in
            DashboardDisplayModel.TrendPoint(id: daySummary.id, date: daySummary.date, sleepScore: daySummary.sleepScore)
        }

        let durationText = durationFormatter.string(from: duration) ?? "—"
        let targetText = durationFormatter.string(from: goal.targetDuration) ?? "—"

        var durationDeltaText: String?
        if let latestTrend = analytics.sevenDayTrend.last {
            let priorDurations = analytics.sevenDayTrend.dropLast().map(\.session.duration)
            if !priorDurations.isEmpty {
                let average = priorDurations.reduce(0, +) / Double(priorDurations.count)
                let delta = latestTrend.session.duration - average
                let sign = delta >= 0 ? "+" : "-"
                let deltaText = durationFormatter.string(from: abs(delta)) ?? "—"
                durationDeltaText = "\(sign)\(deltaText) vs 7-day avg"
            }
        }

        return DashboardDisplayModel(
            greeting: greeting(for: Date()),
            dateText: dateFormatter.string(from: Date()),
            sleepScore: summary.sleepScore,
            latestDurationText: durationText,
            durationDeltaText: durationDeltaText,
            goalProgress: goal.targetDuration > 0 ? min(duration / goal.targetDuration, 1.0) : 0,
            goalProgressText: "\(durationText) of \(targetText) goal",
            stageBreakdown: stageBreakdown,
            sevenDayTrend: sevenDayTrend
        )
    }

    private static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    convenience init(previewState: State) {
        self.init()
        state = previewState
    }
}
