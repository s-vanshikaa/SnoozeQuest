//
//  GoalsViewModel.swift
//  SnoozeQuest
//

import Combine
import Foundation

struct GoalsDisplayModel: Equatable {
    let targetDurationText: String
    let bedtimeText: String
    let wakeTimeText: String
    let completionPercentageText: String
    let streakCount: Int
    let nextWorldText: String?
}

@MainActor
final class GoalsViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(GoalsDisplayModel)
        case error(String)
    }

    @Published private(set) var state: State = .loading

    @Published var targetDuration: TimeInterval = 8 * 3600
    @Published var bedtime: Date = GoalsViewModel.date(fromHour: 22, minute: 30)
    @Published var wakeTime: Date = GoalsViewModel.date(fromHour: 6, minute: 30)
    @Published var validationMessage: String?
    @Published private(set) var isSaving = false
    @Published var didSave = false

    private let goalRepository: GoalRepository
    private let sleepRepository: SleepRepository
    private let analyticsRepository: AnalyticsRepository

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    init(
        goalRepository: GoalRepository = MockGoalRepository(),
        sleepRepository: SleepRepository = MockSleepRepository(),
        analyticsRepository: AnalyticsRepository = MockAnalyticsRepository()
    ) {
        self.goalRepository = goalRepository
        self.sleepRepository = sleepRepository
        self.analyticsRepository = analyticsRepository
    }

    func load() async {
        state = .loading
        do {
            async let goal = goalRepository.fetchGoal()
            async let summaries = sleepRepository.fetchDailySummaries(days: 30)
            async let analytics = analyticsRepository.fetchAnalytics()

            let (fetchedGoal, fetchedSummaries, fetchedAnalytics) = try await (goal, summaries, analytics)

            populateForm(from: fetchedGoal)
            state = .loaded(Self.makeDisplayModel(goal: fetchedGoal, summaries: fetchedSummaries, analytics: fetchedAnalytics))
        } catch {
            state = .error("We couldn't load your goal. Pull to refresh to try again.")
        }
    }

    func save() async {
        validationMessage = nil

        guard targetDuration > 0, targetDuration <= 16 * 3600 else {
            validationMessage = "Target duration must be more than 0 and at most 16 hours."
            return
        }

        let calendar = Calendar.current
        let bedComponents = calendar.dateComponents([.hour, .minute], from: bedtime)
        let wakeComponents = calendar.dateComponents([.hour, .minute], from: wakeTime)

        guard
            let bedHour = bedComponents.hour, let bedMinute = bedComponents.minute,
            let wakeHour = wakeComponents.hour, let wakeMinute = wakeComponents.minute
        else {
            validationMessage = "Please select a valid bedtime and wake time."
            return
        }

        let newGoal = SleepGoal(
            targetDuration: targetDuration,
            bedtime: TimeOfDay(hour: bedHour, minute: bedMinute),
            wakeTime: TimeOfDay(hour: wakeHour, minute: wakeMinute)
        )

        isSaving = true
        defer { isSaving = false }

        do {
            try await goalRepository.saveGoal(newGoal)
            async let summaries = sleepRepository.fetchDailySummaries(days: 30)
            async let analytics = analyticsRepository.fetchAnalytics()
            let (fetchedSummaries, fetchedAnalytics) = try await (summaries, analytics)
            state = .loaded(Self.makeDisplayModel(goal: newGoal, summaries: fetchedSummaries, analytics: fetchedAnalytics))
            SQHaptics.success()
            didSave = true
        } catch {
            validationMessage = "We couldn't save your goal. Please try again."
        }
    }

    private func populateForm(from goal: SleepGoal) {
        targetDuration = goal.targetDuration
        bedtime = Self.date(fromHour: goal.bedtime.hour, minute: goal.bedtime.minute)
        wakeTime = Self.date(fromHour: goal.wakeTime.hour, minute: goal.wakeTime.minute)
    }

    private static func makeDisplayModel(
        goal: SleepGoal,
        summaries: [DailySleepSummary],
        analytics: SleepAnalytics
    ) -> GoalsDisplayModel {
        let completion = summaries.isEmpty ? 0 : Double(summaries.filter(\.goalMet).count) / Double(summaries.count)
        let goalNightsCompleted = summaries.filter(\.goalMet).count
        let journey = JourneyProgressCalculator.compute(goalNightsCompleted: goalNightsCompleted)

        let nextWorldText: String?
        if let nextWorldName = journey.nextWorldName, let remaining = journey.goalNightsUntilNext {
            nextWorldText = "\(remaining) goal night\(remaining == 1 ? "" : "s") until \(nextWorldName)"
        } else {
            nextWorldText = nil
        }

        return GoalsDisplayModel(
            targetDurationText: durationFormatter.string(from: goal.targetDuration) ?? "—",
            bedtimeText: timeFormatter.string(from: date(fromHour: goal.bedtime.hour, minute: goal.bedtime.minute)),
            wakeTimeText: timeFormatter.string(from: date(fromHour: goal.wakeTime.hour, minute: goal.wakeTime.minute)),
            completionPercentageText: "\(Int(completion * 100))%",
            streakCount: analytics.currentStreak,
            nextWorldText: nextWorldText
        )
    }

    private static func date(fromHour hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    convenience init(previewState: State) {
        self.init()
        state = previewState
    }
}
