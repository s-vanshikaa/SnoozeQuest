//
//  GoalSetupView.swift
//  SnoozeQuest
//

import SwiftUI

struct GoalSetupView: View {
    @Binding var targetDuration: TimeInterval
    var isSaving: Bool
    var onConfirm: () -> Void

    private let range: ClosedRange<TimeInterval> = 6 * 3600...10 * 3600

    private var moonProgress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0.5 }
        return (targetDuration - range.lowerBound) / span
    }

    var body: some View {
        VStack(spacing: SQSpacing.xl) {
            Spacer()

            SQSleepMoon(progress: moonProgress, size: 88, breathes: false)

            Text("How much sleep are\nyou aiming for?")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(SQColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            SQDurationSlider(duration: $targetDuration, range: range)
                .padding(.horizontal, SQSpacing.xl)

            Spacer()

            Button {
                onConfirm()
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(.sqPrimary)
            .disabled(isSaving)
            .padding(.horizontal, SQSpacing.screenHorizontal)
        }
        .padding(.vertical, SQSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SQColor.background)
    }
}

#Preview {
    GoalSetupView(targetDuration: .constant(8 * 3600), isSaving: false, onConfirm: {})
}
