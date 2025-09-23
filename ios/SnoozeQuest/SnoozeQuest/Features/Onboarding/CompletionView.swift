//
//  CompletionView.swift
//  SnoozeQuest
//

import SwiftUI

struct CompletionView: View {
    var targetDuration: TimeInterval
    var onEnter: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    private var durationText: String {
        Self.durationFormatter.string(from: targetDuration) ?? "—"
    }

    var body: some View {
        ZStack {
            SQColor.surfaceDeep.ignoresSafeArea()
            SQStarfield(starCount: 30).ignoresSafeArea()

            VStack(spacing: SQSpacing.xxl) {
                Spacer()

                Image(systemName: "sparkle")
                    .font(.system(size: 28))
                    .foregroundStyle(SQColor.moonlight)

                Text("Your journey begins tonight.")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SQColor.textPrimary)
                    .padding(.horizontal, SQSpacing.xl)

                HStack(spacing: SQSpacing.xxxl) {
                    milestone(title: "Sleep Goal", value: durationText)

                    VStack(spacing: SQSpacing.xs) {
                        SQPlanet(
                            world: WorldDisplay(id: 0, name: "Earth", state: .current, requiredGoalNights: 0),
                            size: 40,
                            showsLabel: false
                        )
                        Text("First World")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SQColor.textSecondary)
                        Text("Earth")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SQColor.textPrimary)
                    }
                }

                Spacer()

                Button("Enter SnoozeQuest", action: onEnter)
                    .buttonStyle(.sqPrimary)
                    .padding(.horizontal, SQSpacing.screenHorizontal)
            }
            .padding(.vertical, SQSpacing.xxl)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96)
        .onAppear {
            withAnimation(SQMotion.transition(reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }

    private func milestone(title: String, value: String) -> some View {
        VStack(spacing: SQSpacing.xs) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SQColor.textSecondary)
            Text(value)
                .font(.sqMetricLarge)
                .monospacedDigit()
                .foregroundStyle(SQColor.textPrimary)
        }
    }
}

#Preview {
    CompletionView(targetDuration: 8 * 3600, onEnter: {})
}
