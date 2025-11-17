//
//  DashboardView.swift
//  SnoozeQuest
//

import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel(
        sleepRepository: AppEnvironment.sleepRepository,
        goalRepository: AppEnvironment.goalRepository,
        analyticsRepository: AppEnvironment.analyticsRepository
    )
    @StateObject private var journeyViewModel = JourneyViewModel(
        sleepRepository: AppEnvironment.sleepRepository,
        analyticsRepository: AppEnvironment.analyticsRepository
    )
    @StateObject private var weeklyInsightViewModel = WeeklyInsightViewModel(
        weeklyInsightRepository: AppEnvironment.weeklyInsightRepository
    )
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentAppeared = false
    @State private var isShowingJourney = false
    @State private var isShowingWeeklyInsight = false

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            content
                .background(SQColor.background)
                .toolbar(.hidden, for: .navigationBar)
                .task {
                    async let dashboardLoad: Void = viewModel.load()
                    async let journeyLoad: Void = journeyViewModel.load()
                    async let weeklyInsightLoad: Void = weeklyInsightViewModel.load()
                    _ = await (dashboardLoad, journeyLoad, weeklyInsightLoad)
                    revealContent()
                }
                .refreshable {
                    async let dashboardLoad: Void = viewModel.load()
                    async let journeyLoad: Void = journeyViewModel.load()
                    async let weeklyInsightLoad: Void = weeklyInsightViewModel.load()
                    _ = await (dashboardLoad, journeyLoad, weeklyInsightLoad)
                }
                .navigationDestination(isPresented: $isShowingJourney) {
                    JourneyView()
                }
                .navigationDestination(isPresented: $isShowingWeeklyInsight) {
                    WeeklyInsightView(state: weeklyInsightViewModel.state)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading your sleep data…")
                .tint(SQColor.moonlight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SQColor.background)

        case .empty:
            SQEmptyState(
                title: "No Sleep Data Yet",
                systemImage: "moon.zzz",
                message: "Log a night of sleep to see your dashboard."
            )
            .background(SQColor.background)

        case .error(let message):
            SQEmptyState(
                title: "Something Went Wrong",
                systemImage: "exclamationmark.triangle",
                message: message
            )
            .background(SQColor.background)

        case .loaded(let dashboard):
            ScrollView {
                VStack(alignment: .leading, spacing: SQSpacing.xxl) {
                    header(dashboard)
                    scoreHero(dashboard)
                    stagesSection(dashboard)
                        .appearing(delay: 1, appeared: contentAppeared, reduceMotion: reduceMotion)
                    journeySection()
                        .appearing(delay: 2, appeared: contentAppeared, reduceMotion: reduceMotion)
                    trendSection(dashboard)
                        .appearing(delay: 3, appeared: contentAppeared, reduceMotion: reduceMotion)
                    goalSection(dashboard)
                        .appearing(delay: 4, appeared: contentAppeared, reduceMotion: reduceMotion)
                    insightSection()
                        .appearing(delay: 5, appeared: contentAppeared, reduceMotion: reduceMotion)
                }
                .padding(.horizontal, SQSpacing.screenHorizontal)
                .padding(.top, SQSpacing.md)
                .padding(.bottom, SQSpacing.xxl)
            }
            .background(SQColor.background)
        }
    }

    private func revealContent() {
        contentAppeared = true
    }

    private func header(_ dashboard: DashboardDisplayModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dashboard.greeting)
                .font(.sqScreenTitle)
                .foregroundStyle(SQColor.textPrimary)
            Text(dashboard.dateText)
                .font(.subheadline)
                .foregroundStyle(SQColor.textSecondary)
        }
        .padding(.top, SQSpacing.sm)
    }

    private func scoreHero(_ dashboard: DashboardDisplayModel) -> some View {
        VStack(spacing: SQSpacing.lg) {
            SQCosmicHero(
                progress: Double(dashboard.sleepScore) / 100,
                value: "\(dashboard.sleepScore)",
                label: "Sleep Score",
                size: 220
            )

            VStack(spacing: SQSpacing.xs) {
                Text(dashboard.latestDurationText)
                    .font(.sqMetricLarge)
                    .monospacedDigit()
                    .foregroundStyle(SQColor.textPrimary)

                if let delta = dashboard.durationDeltaText {
                    SQMetricPill(text: delta, tint: delta.hasPrefix("+") ? SQColor.success : SQColor.warning)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SQSpacing.sm)
    }

    private func stagesSection(_ dashboard: DashboardDisplayModel) -> some View {
        VStack(alignment: .leading, spacing: SQSpacing.md) {
            SQSectionHeader(title: "Last Night")

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(dashboard.stageBreakdown) { breakdown in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(SQColor.stage(breakdown.stage))
                            .frame(width: geometry.size.width * breakdown.percentage)
                    }
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)

            HStack(spacing: SQSpacing.md) {
                ForEach(dashboard.stageBreakdown) { breakdown in
                    SQSleepStageBadge(stage: breakdown.stage, detail: "\(Int(breakdown.percentage * 100))%")
                }
            }
        }
    }

    @ViewBuilder
    private func journeySection() -> some View {
        if case .loaded(let journey) = journeyViewModel.state {
            SQJourneyCard(journey: journey) {
                SQHaptics.selectionChanged()
                isShowingJourney = true
            }
        }
    }

    private func trendSection(_ dashboard: DashboardDisplayModel) -> some View {
        VStack(alignment: .leading, spacing: SQSpacing.md) {
            SQSectionHeader(title: "This Week")

            Chart(dashboard.sevenDayTrend) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Sleep Score", point.sleepScore)
                )
                .foregroundStyle(SQColor.skyBlue.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 140)
            .accessibilityLabel("7 day sleep score trend")
            .accessibilityValue(trendAccessibilitySummary(dashboard))
        }
    }

    private func trendAccessibilitySummary(_ dashboard: DashboardDisplayModel) -> String {
        dashboard.sevenDayTrend
            .map { "\(Self.weekdayFormatter.string(from: $0.date)) \($0.sleepScore)" }
            .joined(separator: ", ")
    }

    private func goalSection(_ dashboard: DashboardDisplayModel) -> some View {
        VStack(alignment: .leading, spacing: SQSpacing.md) {
            SQSectionHeader(title: "Your Goal")

            HStack(spacing: SQSpacing.lg) {
                ZStack {
                    SQProgressRing(progress: dashboard.goalProgress, tint: SQColor.skyBlue)
                    Text("\(Int(dashboard.goalProgress * 100))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SQColor.textPrimary)
                }
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

                Text(dashboard.goalProgressText)
                    .font(.subheadline)
                    .foregroundStyle(SQColor.textSecondary)

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(Int(dashboard.goalProgress * 100)) percent")
        }
    }

    private func insightSection() -> some View {
        VStack(alignment: .leading, spacing: SQSpacing.md) {
            SQSectionHeader(title: "Weekly Insight")

            Button {
                SQHaptics.selectionChanged()
                isShowingWeeklyInsight = true
            } label: {
                HStack(alignment: .top, spacing: SQSpacing.sm) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(SQColor.moonlight)
                    Text(weeklyInsightPreviewText)
                        .font(.subheadline)
                        .foregroundStyle(SQColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if isWeeklyInsightTappable {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(SQColor.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isWeeklyInsightTappable == false)
        }
    }

    private var weeklyInsightPreviewText: String {
        switch weeklyInsightViewModel.state {
        case .loading:
            return "Loading this week's insight…"
        case .available(let insight):
            return insight.summaryText ?? "Your weekly insight isn't ready yet — check back soon."
        case .unavailable:
            return "Weekly insight unavailable right now."
        }
    }

    private var isWeeklyInsightTappable: Bool {
        if case .available = weeklyInsightViewModel.state { return true }
        return false
    }
}

private extension View {
    func appearing(delay: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(
                reduceMotion
                    ? .easeInOut(duration: SQMotion.fast)
                    : .easeOut(duration: SQMotion.standard).delay(Double(delay) * SQMotion.staggerDelay),
                value: appeared
            )
    }
}

#Preview("Loaded") {
    DashboardView()
}

#Preview("Empty") {
    DashboardPreviewContainer(state: .empty)
}

#Preview("Error") {
    DashboardPreviewContainer(state: .error("We couldn't load your sleep data. Pull to refresh to try again."))
}

private struct DashboardPreviewContainer: View {
    let state: DashboardViewModel.State

    var body: some View {
        DashboardView(previewState: state)
    }
}

private extension DashboardView {
    init(previewState: DashboardViewModel.State) {
        self.init()
        _viewModel = StateObject(wrappedValue: DashboardViewModel(previewState: previewState))
    }
}
