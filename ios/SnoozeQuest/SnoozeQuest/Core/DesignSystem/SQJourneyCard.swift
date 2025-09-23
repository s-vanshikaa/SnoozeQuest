//
//  SQJourneyCard.swift
//  SnoozeQuest
//
//  Dashboard entry point into the Journey screen.
//

import SwiftUI

struct SQJourneyCard: View {
    let journey: JourneyDisplayModel
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: SQSpacing.md) {
                HStack {
                    SQSectionHeader(title: "Your Journey")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SQColor.textTertiary)
                }

                HStack(spacing: SQSpacing.md) {
                    SQPlanet(world: journey.currentWorld, size: 40, showsLabel: false)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(journey.currentWorld.name)
                            .font(.headline)
                            .foregroundStyle(SQColor.textPrimary)

                        if let nextWorldName = journey.nextWorldName, let remaining = journey.goalNightsUntilNext {
                            Text("\(remaining) goal night\(remaining == 1 ? "" : "s") to \(nextWorldName)")
                                .font(.caption)
                                .foregroundStyle(SQColor.textSecondary)
                        } else {
                            Text("All worlds unlocked")
                                .font(.caption)
                                .foregroundStyle(SQColor.textSecondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                SQProgressBar(progress: journey.progressToNextWorld, tint: SQColor.moonlight)
            }
            .padding(SQSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: SQRadius.card, style: .continuous)
                    .fill(SQColor.surfaceDeep)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your Journey")
    }
}
