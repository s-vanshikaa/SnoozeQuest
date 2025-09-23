//
//  HistoryViewModel.swift
//  SnoozeQuest
//

import Combine
import Foundation

struct HistoryDisplayModel: Equatable {
    struct DayPoint: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let durationHours: Double
        let sleepScore: Int
        let stagePercentages: [SleepStage: Double]
        let goalMet: Bool
    }

    struct SessionRow: Identifiable, Equatable {
        let id: UUID
        let dateText: String
        let durationText: String
        let sleepScore: Int
        let goalMet: Bool
    }

    let averageDurationText: String
    let averageScoreText: String
    let goalsMetText: String
    let dayPoints: [DayPoint]
    let sessionRows: [SessionRow]
}

@MainActor
final class HistoryViewModel: ObservableObject {
    enum RangeSelection: Int, CaseIterable, Identifiable, Hashable {
        case week = 7
        case month = 30

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .week: return "7D"
            case .month: return "30D"
            }
        }
    }

    enum MetricSelection: String, CaseIterable, Identifiable, Hashable {
        case duration = "Duration"
        case score = "Score"
        case stages = "Stages"

        var id: String { rawValue }
    }

    enum State: Equatable {
        case loading
        case loaded(HistoryDisplayModel)
        case empty
        case error(String)
    }

    @Published var selectedRange: RangeSelection = .week
    @Published var selectedMetric: MetricSelection = .duration
    @Published private(set) var state: State = .loading

    private let sleepRepository: SleepRepository

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter
    }()

    init(sleepRepository: SleepRepository = MockSleepRepository()) {
        self.sleepRepository = sleepRepository
    }

    func load() async {
        state = .loading
        do {
            let summaries = try await sleepRepository.fetchDailySummaries(days: selectedRange.rawValue)
            guard !summaries.isEmpty else {
                state = .empty
                return
            }
            state = .loaded(Self.makeDisplayModel(summaries: summaries))
        } catch {
            state = .error("We couldn't load your sleep history. Pull to refresh to try again.")
        }
    }

    private static func makeDisplayModel(summaries: [DailySleepSummary]) -> HistoryDisplayModel {
        let averageDuration = summaries.map(\.session.duration).reduce(0, +) / Double(summaries.count)
        let averageScore = summaries.map(\.sleepScore).reduce(0, +) / summaries.count
        let goalsMet = summaries.filter(\.goalMet).count

        let dayPoints = summaries.map { summary -> HistoryDisplayModel.DayPoint in
            let stageTotal = summary.session.stageDurations.values.reduce(0, +)
            let stagePercentages = Dictionary(uniqueKeysWithValues: SleepStage.allCases.map { stage in
                (stage, stageTotal > 0 ? (summary.session.stageDurations[stage] ?? 0) / stageTotal : 0)
            })

            return HistoryDisplayModel.DayPoint(
                id: summary.id,
                date: summary.date,
                durationHours: summary.session.duration / 3600,
                sleepScore: summary.sleepScore,
                stagePercentages: stagePercentages,
                goalMet: summary.goalMet
            )
        }

        let sessionRows = summaries.reversed().map { summary in
            HistoryDisplayModel.SessionRow(
                id: summary.id,
                dateText: dayFormatter.string(from: summary.date),
                durationText: durationFormatter.string(from: summary.session.duration) ?? "—",
                sleepScore: summary.sleepScore,
                goalMet: summary.goalMet
            )
        }

        return HistoryDisplayModel(
            averageDurationText: durationFormatter.string(from: averageDuration) ?? "—",
            averageScoreText: "\(averageScore)",
            goalsMetText: "\(goalsMet)/\(summaries.count) nights",
            dayPoints: dayPoints,
            sessionRows: sessionRows
        )
    }

    convenience init(previewState: State) {
        self.init()
        state = previewState
    }
}
