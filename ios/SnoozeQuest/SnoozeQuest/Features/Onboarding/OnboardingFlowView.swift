//
//  OnboardingFlowView.swift
//  SnoozeQuest
//
//  Coordinates Welcome -> Onboarding cards -> Goal Setup -> Completion.
//

import SwiftUI

struct OnboardingFlowView: View {
    @StateObject private var viewModel: OnboardingViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onFinish: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: OnboardingViewModel(onFinish: onFinish))
    }

    var body: some View {
        ZStack {
            SQColor.background.ignoresSafeArea()

            switch viewModel.step {
            case .welcome:
                WelcomeView(onGetStarted: viewModel.goToCards)
                    .transition(stepTransition)

            case .cards:
                OnboardingCardsView(
                    cardIndex: $viewModel.cardIndex,
                    onContinue: viewModel.goToGoalSetup,
                    onSkip: viewModel.skipToEnd
                )
                .transition(stepTransition)

            case .goalSetup:
                GoalSetupView(
                    targetDuration: $viewModel.targetDuration,
                    isSaving: viewModel.isSavingGoal,
                    onConfirm: { Task { await viewModel.confirmGoal() } }
                )
                .transition(stepTransition)

            case .completion:
                CompletionView(targetDuration: viewModel.targetDuration, onEnter: viewModel.finish)
                    .transition(stepTransition)
            }
        }
        .animation(SQMotion.transition(reduceMotion: reduceMotion), value: isStepIdentity)
    }

    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }

    /// A hashable projection of the current step so `.animation(value:)` can key off it.
    private var isStepIdentity: Int {
        switch viewModel.step {
        case .welcome: return 0
        case .cards: return 1
        case .goalSetup: return 2
        case .completion: return 3
        }
    }
}

#Preview {
    OnboardingFlowView(onFinish: {})
}
