//
//  HistoryView.swift
//  SnoozeQuest
//

import SwiftUI
import Charts

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            content
                .background(SQColor.background)
                .navigationTitle("History")
                .task(id: viewModel.selectedRange) { await viewModel.load() }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SQSpacing.xl) {
                controls

                switch viewModel.state {
                case .loading:
                    ProgressView("Loading history…")
                        .tint(SQColor.moonlight)
                        .frame(maxWidth: .infinity)
                        .padding(.top, SQSpacing.xxxl)

                case .empty:
                    SQEmptyState(
                        title: "No Sleep Data Yet",
                        systemImage: "moon.zzz",
                        message: "Log a night of sleep to see your history."
                    )
                    .padding(.top, SQSpacing.xl)

                case .error(let message):
                    SQEmptyState(
                        title: "Something Went Wrong",
                        systemImage: "exclamationmark.triangle",
                        message: message
                    )
                    .padding(.top, SQSpacing.xl)

                case .loaded(let history):
                    overview(history)
                    HistoryChartView(dayPoints: history.dayPoints, metric: viewModel.selectedMetric)
                    sessionsList(history)
                }
            }
            .padding(.horizontal, SQSpacing.screenHorizontal)
            .padding(.vertical, SQSpacing.md)
        }
    }

    private var controls: some View {
        VStack(spacing: SQSpacing.sm) {
            Picker("Metric", selection: $viewModel.selectedMetric) {
                ForEach(HistoryViewModel.MetricSelection.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)

            Picker("Range", selection: $viewModel.selectedRange) {
                ForEach(HistoryViewModel.RangeSelection.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func overview(_ history: HistoryDisplayModel) -> some View {
        HStack(spacing: 0) {
            overviewMetric("Avg Duration", history.averageDurationText)
            Divider().frame(height: 32)
            overviewMetric("Avg Score", history.averageScoreText)
            Divider().frame(height: 32)
            overviewMetric("Goals Met", history.goalsMetText)
        }
    }

    private func overviewMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(SQColor.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(SQColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sessionsList(_ history: HistoryDisplayModel) -> some View {
        VStack(alignment: .leading, spacing: SQSpacing.md) {
            SQSectionHeader(title: "Sessions")

            VStack(spacing: 0) {
                ForEach(Array(history.sessionRows.enumerated()), id: \.element.id) { index, row in
                    sessionRow(row)
                    if index < history.sessionRows.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private func sessionRow(_ row: HistoryDisplayModel.SessionRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.dateText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SQColor.textPrimary)
                Text(row.durationText)
                    .font(.caption)
                    .foregroundStyle(SQColor.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(row.sleepScore)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SQColor.textPrimary)
                Image(systemName: row.goalMet ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(row.goalMet ? SQColor.success : SQColor.textTertiary)
            }
        }
        .padding(.vertical, SQSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryChartView: View {
    let dayPoints: [HistoryDisplayModel.DayPoint]
    let metric: HistoryViewModel.MetricSelection

    @State private var selectedID: UUID?

    private var selectedPoint: HistoryDisplayModel.DayPoint? {
        dayPoints.first { $0.id == selectedID }
    }

    var body: some View {
        Chart(dayPoints) { point in
            marks(for: point)
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .frame(height: 180)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )

                    if let point = selectedPoint, let xPosition = proxy.position(forX: point.date) {
                        tooltip(for: point)
                            .fixedSize()
                            .position(x: clampedX(xPosition, in: geometry.size.width), y: 16)
                    }
                }
            }
        }
        .onChange(of: metric) { _, _ in selectedID = nil }
        .accessibilityLabel("\(metric.rawValue) by day")
        .accessibilityValue(accessibilitySummary)
    }

    @ChartContentBuilder
    private func marks(for point: HistoryDisplayModel.DayPoint) -> some ChartContent {
        switch metric {
        case .duration:
            BarMark(x: .value("Day", point.date, unit: .day), y: .value("Hours", point.durationHours))
                .foregroundStyle(point.id == selectedID ? SQColor.moonlight : SQColor.skyBlue)
                .cornerRadius(4)
        case .score:
            BarMark(x: .value("Day", point.date, unit: .day), y: .value("Score", point.sleepScore))
                .foregroundStyle(point.id == selectedID ? SQColor.moonlight : SQColor.skyBlue)
                .cornerRadius(4)
        case .stages:
            ForEach(SleepStage.allCases, id: \.self) { stage in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Percent", point.stagePercentages[stage] ?? 0)
                )
                .foregroundStyle(SQColor.stage(stage))
                .opacity(selectedID == nil || point.id == selectedID ? 1 : 0.4)
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        switch metric {
        case .duration: return 0...12
        case .score: return 0...100
        case .stages: return 0...1
        }
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let frame = geometry[proxy.plotAreaFrame]
        let xPosition = location.x - frame.origin.x
        guard
            xPosition >= 0, xPosition <= frame.width,
            let date: Date = proxy.value(atX: xPosition),
            let nearest = dayPoints.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
        else { return }

        if nearest.id != selectedID {
            selectedID = nearest.id
            SQHaptics.selectionChanged()
        }
    }

    private func clampedX(_ x: CGFloat, in width: CGFloat) -> CGFloat {
        min(max(x, 44), max(width - 44, 44))
    }

    private func tooltip(for point: HistoryDisplayModel.DayPoint) -> some View {
        HStack(spacing: SQSpacing.sm) {
            Text(Self.tooltipDateFormatter.string(from: point.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(SQColor.textSecondary)
            Text(tooltipValue(for: point))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(SQColor.textPrimary)
        }
        .padding(.horizontal, SQSpacing.md)
        .padding(.vertical, SQSpacing.xs)
        .background(SQColor.surface, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    private func tooltipValue(for point: HistoryDisplayModel.DayPoint) -> String {
        switch metric {
        case .duration:
            let hours = Int(point.durationHours)
            let minutes = Int((point.durationHours - Double(hours)) * 60)
            return String(format: "%dh %02dm", hours, minutes)
        case .score:
            return "\(point.sleepScore)"
        case .stages:
            return SleepStage.allCases
                .map { "\(Int((point.stagePercentages[$0] ?? 0) * 100))%" }
                .joined(separator: " · ")
        }
    }

    private var accessibilitySummary: String {
        dayPoints
            .map { "\(Self.tooltipDateFormatter.string(from: $0.date)) \(tooltipValue(for: $0))" }
            .joined(separator: ", ")
    }

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
}

#Preview("Loaded") {
    HistoryView()
}

#Preview("Empty") {
    HistoryPreviewContainer(state: .empty)
}

#Preview("Error") {
    HistoryPreviewContainer(state: .error("We couldn't load your sleep history. Pull to refresh to try again."))
}

private struct HistoryPreviewContainer: View {
    let state: HistoryViewModel.State

    var body: some View {
        HistoryView(previewState: state)
    }
}

private extension HistoryView {
    init(previewState: HistoryViewModel.State) {
        self.init()
        _viewModel = StateObject(wrappedValue: HistoryViewModel(previewState: previewState))
    }
}
