//
//  WeeklyInsightView.swift
//  SnoozeQuest
//

import SwiftUI

struct WeeklyInsightView: View {
    let state: WeeklyInsightViewModel.State

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    var body: some View {
        ZStack {
            SQColor.background.ignoresSafeArea()
            content
        }
        .navigationTitle("Weekly Insight")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("Loading your weekly insight…")
                .tint(SQColor.moonlight)

        case .unavailable:
            SQEmptyState(
                title: "Insight Unavailable",
                systemImage: "sparkle",
                message: "We couldn't load your weekly insight. Pull to refresh on Dashboard to try again."
            )

        case .available(let insight):
            ScrollView {
                VStack(alignment: .leading, spacing: SQSpacing.xl) {
                    summarySection(insight)
                    metricsSection(insight)
                }
                .padding(.horizontal, SQSpacing.screenHorizontal)
                .padding(.vertical, SQSpacing.xl)
            }
        }
    }

    private func summarySection(_ insight: WeeklyInsight) -> some View {
        VStack(alignment: .leading, spacing: SQSpacing.md) {
            SQSectionHeader(title: "This Week")

            HStack(alignment: .top, spacing: SQSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundStyle(SQColor.moonlight)
                Text(insight.summaryText ?? "We couldn't generate an interpretation this week — your metrics are still below.")
                    .font(.body)
                    .foregroundStyle(SQColor.textPrimary)
            }
        }
    }

    private func metricsSection(_ insight: WeeklyInsight) -> some View {
        VStack(alignment: .leading, spacing: SQSpacing.md) {
            SQSectionHeader(title: "Supporting Metrics")

            VStack(spacing: SQSpacing.sm) {
                metricRow("Average Sleep", value: durationText(insight.metrics.averageSleepMinutes))
                metricRow("Duration Trend", value: signedDurationText(insight.metrics.durationChangeMinutes))
                metricRow("Bedtime Trend", value: signedDurationText(insight.metrics.bedtimeChangeMinutes))
                metricRow("Goal Completion", value: "\(Int((insight.metrics.goalCompletionRate * 100).rounded()))%")
                metricRow("Average Sleep Score", value: "\(Int(insight.metrics.averageSleepScore.rounded()))")
            }
        }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(SQColor.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(SQColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func durationText(_ minutes: Double) -> String {
        Self.durationFormatter.string(from: minutes * 60) ?? "—"
    }

    private func signedDurationText(_ minutes: Double) -> String {
        let sign = minutes >= 0 ? "+" : "-"
        let text = Self.durationFormatter.string(from: abs(minutes) * 60) ?? "—"
        return "\(sign)\(text)"
    }
}

#Preview("Available") {
    NavigationStack {
        WeeklyInsightView(state: .available(MockSleepData.weeklyInsight))
    }
}

#Preview("Unavailable") {
    NavigationStack {
        WeeklyInsightView(state: .unavailable)
    }
}
