//
//  SQDurationSlider.swift
//  SnoozeQuest
//
//  Interactive duration control shared by onboarding Goal Setup and the Goals screen.
//

import SwiftUI

struct SQDurationSlider: View {
    @Binding var duration: TimeInterval
    var range: ClosedRange<TimeInterval> = 6 * 3600...10 * 3600
    var step: TimeInterval = 15 * 60

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: SQSpacing.lg) {
            Text(durationText)
                .font(.sqMetricHero)
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(SQMotion.interactive(reduceMotion: reduceMotion), value: duration)
                .foregroundStyle(SQColor.textPrimary)
                .accessibilityHidden(true)

            VStack(spacing: SQSpacing.xs) {
                Slider(
                    value: Binding(
                        get: { duration },
                        set: { newValue in
                            let stepped = (newValue / step).rounded() * step
                            if stepped != duration {
                                duration = stepped
                                SQHaptics.selectionChanged()
                            }
                        }
                    ),
                    in: range
                )
                .tint(SQColor.skyBlue)

                HStack {
                    Text(boundLabel(range.lowerBound))
                    Spacer()
                    Text(boundLabel(range.upperBound))
                }
                .font(.caption)
                .foregroundStyle(SQColor.textSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Target sleep duration")
        .accessibilityValue(durationText)
    }

    private var durationText: String {
        let totalMinutes = Int((duration / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return String(format: "%dh %02dm", hours, minutes)
    }

    private func boundLabel(_ interval: TimeInterval) -> String {
        "\(Int(interval / 3600))h"
    }
}
