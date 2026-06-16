//
//  PlanetDetailView.swift
//  SnoozeQuest
//

import SwiftUI

struct PlanetDetailView: View {
    let detail: WorldMilestoneDetail

    var body: some View {
        VStack(spacing: SQSpacing.xl) {
            SQPlanet(world: detail.world, size: 96, showsLabel: false)
                .padding(.top, SQSpacing.xl)

            VStack(spacing: SQSpacing.xs) {
                Text(detail.world.name.uppercased())
                    .font(.title.weight(.bold))
                    .foregroundStyle(SQColor.textPrimary)
                Text(detail.unlockedAfterText)
                    .font(.subheadline)
                    .foregroundStyle(SQColor.textSecondary)
            }

            HStack(spacing: SQSpacing.xxl) {
                metric(title: "Average Sleep Score", value: detail.averageScoreText)
                metric(title: "Longest Streak", value: detail.longestStreakText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SQSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SQColor.surfaceDeep)
        .presentationDetents([.medium])
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: SQSpacing.xs) {
            Text(value)
                .font(.sqMetricLarge)
                .monospacedDigit()
                .foregroundStyle(SQColor.moonlight)
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SQColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    PlanetDetailView(
        detail: WorldMilestoneDetail(
            world: WorldDisplay(id: 1, name: "Mars", state: .current, requiredGoalNights: 4),
            unlockedAfterText: "Unlocked after 4 goal nights",
            averageScoreText: "84",
            longestStreakText: "9 nights"
        )
    )
}
