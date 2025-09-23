//
//  OnboardingViewModel.swift
//  SnoozeQuest
//

import Combine
import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step {
        case welcome
        case cards
        case goalSetup
        case completion
    }

    @Published private(set) var step: Step = .welcome
    @Published var cardIndex: Int = 0
    @Published var targetDuration: TimeInterval = 8 * 3600
    @Published private(set) var isSavingGoal = false

    private let goalRepository: GoalRepository
    private let onFinish: () -> Void

    init(goalRepository: GoalRepository = MockGoalRepository(), onFinish: @escaping () -> Void) {
        self.goalRepository = goalRepository
        self.onFinish = onFinish
    }

    func goToCards() {
        step = .cards
    }

    func goToGoalSetup() {
        step = .goalSetup
    }

    func skipToEnd() {
        onFinish()
    }

    func confirmGoal() async {
        isSavingGoal = true
        defer { isSavingGoal = false }

        var goal = (try? await goalRepository.fetchGoal()) ?? SleepGoal(
            targetDuration: targetDuration,
            bedtime: TimeOfDay(hour: 22, minute: 30),
            wakeTime: TimeOfDay(hour: 6, minute: 30)
        )
        goal.targetDuration = targetDuration
        try? await goalRepository.saveGoal(goal)

        SQHaptics.success()
        step = .completion
    }

    func finish() {
        SQHaptics.success()
        onFinish()
    }
}
