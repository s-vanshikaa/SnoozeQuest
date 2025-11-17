//
//  WeeklyInsightViewModel.swift
//  SnoozeQuest
//

import Combine
import Foundation

@MainActor
final class WeeklyInsightViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case available(WeeklyInsight)
        case unavailable
    }

    @Published private(set) var state: State = .loading

    private let weeklyInsightRepository: WeeklyInsightRepository

    init(weeklyInsightRepository: WeeklyInsightRepository = MockWeeklyInsightRepository()) {
        self.weeklyInsightRepository = weeklyInsightRepository
    }

    func load() async {
        state = .loading
        do {
            state = .available(try await weeklyInsightRepository.fetchWeeklyInsight())
        } catch {
            state = .unavailable
        }
    }

    convenience init(previewState: State) {
        self.init()
        state = previewState
    }
}
