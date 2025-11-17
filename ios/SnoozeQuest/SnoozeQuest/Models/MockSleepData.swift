//
//  MockSleepData.swift
//  SnoozeQuest
//
//  Deterministic mock data for previews and mock repositories.
//

import Foundation

enum MockSleepData {
    static let goal = SleepGoal(
        targetDuration: 8 * 3600,
        bedtime: TimeOfDay(hour: 22, minute: 30),
        wakeTime: TimeOfDay(hour: 6, minute: 30)
    )

    static let dailySummaries: [DailySleepSummary] = generateDailySummaries()

    static let sessions: [SleepSession] = dailySummaries.map(\.session)

    static let analytics: SleepAnalytics = generateAnalytics(from: dailySummaries)

    static let weeklyInsight: WeeklyInsight = generateWeeklyInsight(from: analytics)

    static let leaderboard: [LeaderboardEntry] = generateLeaderboard()

    private static func generateDailySummaries(days: Int = 30) -> [DailySleepSummary] {
        var generator = SeededGenerator(seed: 42)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var summaries: [DailySleepSummary] = []
        summaries.reserveCapacity(days)

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard
                let day = calendar.date(byAdding: .day, value: -offset, to: today),
                let previousDay = calendar.date(byAdding: .day, value: -1, to: day),
                let bedtimeAnchor = calendar.date(bySettingHour: goal.bedtime.hour, minute: goal.bedtime.minute, second: 0, of: previousDay)
            else { continue }

            let jitterMinutes = Int.random(in: -45...45, using: &generator)
            guard let startDate = calendar.date(byAdding: .minute, value: jitterMinutes, to: bedtimeAnchor) else { continue }

            let durationHours = Double.random(in: 5.0...9.0, using: &generator)
            let duration = durationHours * 3600
            let endDate = startDate.addingTimeInterval(duration)

            let awake = duration * Double.random(in: 0.02...0.08, using: &generator)
            let rem = duration * Double.random(in: 0.15...0.25, using: &generator)
            let deep = duration * Double.random(in: 0.10...0.20, using: &generator)
            let core = max(duration - awake - rem - deep, 0)

            let session = SleepSession(
                id: UUID(),
                startDate: startDate,
                endDate: endDate,
                stageDurations: [
                    .awake: awake,
                    .rem: rem,
                    .core: core,
                    .deep: deep
                ]
            )

            let goalMet = duration >= goal.targetDuration * 0.95
            let score = mockSleepScore(duration: duration, deep: deep, rem: rem, awake: awake)

            summaries.append(
                DailySleepSummary(
                    id: UUID(),
                    date: day,
                    session: session,
                    sleepScore: score,
                    goalMet: goalMet
                )
            )
        }

        return summaries
    }

    /// Rough heuristic used only to make mock scores look plausible; not the real scoring algorithm.
    private static func mockSleepScore(duration: TimeInterval, deep: TimeInterval, rem: TimeInterval, awake: TimeInterval) -> Int {
        let durationScore = min(duration / (8 * 3600), 1.0) * 60
        let qualityScore = min((deep + rem) / duration, 0.5) * 60
        let awakePenalty = (awake / duration) * 20
        let raw = durationScore + qualityScore - awakePenalty
        return Int(min(max(raw, 0), 100))
    }

    private static func generateAnalytics(from summaries: [DailySleepSummary]) -> SleepAnalytics {
        guard !summaries.isEmpty else {
            return SleepAnalytics(averageSleepScore: 0, averageDuration: 0, currentStreak: 0, sevenDayTrend: [])
        }

        let averageScore = summaries.map(\.sleepScore).reduce(0, +) / summaries.count
        let averageDuration = summaries.map(\.session.duration).reduce(0, +) / Double(summaries.count)

        var streak = 0
        for summary in summaries.reversed() {
            if summary.goalMet {
                streak += 1
            } else {
                break
            }
        }

        let sevenDayTrend = Array(summaries.suffix(7))

        return SleepAnalytics(
            averageSleepScore: averageScore,
            averageDuration: averageDuration,
            currentStreak: streak,
            sevenDayTrend: sevenDayTrend
        )
    }

    private static func generateWeeklyInsight(from analytics: SleepAnalytics) -> WeeklyInsight {
        let summaryText: String
        if analytics.averageSleepScore >= 80 {
            summaryText = "Great week! Your sleep consistency is paying off."
        } else if analytics.averageSleepScore >= 60 {
            summaryText = "Decent week. A slightly earlier bedtime could help."
        } else {
            summaryText = "Your sleep took a hit this week — aim for more consistent bedtimes."
        }

        return WeeklyInsight(
            weekStartDate: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            metrics: WeeklyInsightMetrics(
                averageSleepMinutes: analytics.averageDuration / 60,
                // Fixed, plausible-looking placeholders: computing the real within-week trend
                // would need the daily summaries split in half, which SleepAnalytics doesn't keep.
                durationChangeMinutes: 12,
                bedtimeChangeMinutes: -5,
                goalCompletionRate: min(Double(analytics.currentStreak) / 7, 1.0),
                averageSleepScore: Double(analytics.averageSleepScore)
            ),
            summaryText: summaryText
        )
    }

    private static func generateLeaderboard() -> [LeaderboardEntry] {
        let names = [
            "You", "Jordan Lee", "Priya Patel", "Sam Rivera", "Alex Chen",
            "Morgan Blake", "Taylor Kim", "Casey Nguyen", "Riley Brooks", "Jamie Ortiz"
        ]

        var generator = SeededGenerator(seed: 7)

        let scored = names
            .map { name -> (name: String, score: Int, goals: Int) in
                let score = Int.random(in: 55...96, using: &generator)
                let goals = Int.random(in: 2...7, using: &generator)
                return (name, score, goals)
            }
            .sorted { $0.score > $1.score }

        return scored.enumerated().map { index, entry in
            LeaderboardEntry(
                id: UUID(),
                rank: index + 1,
                displayName: entry.name,
                averageSleepScore: entry.score,
                goalsCompleted: entry.goals,
                isCurrentUser: entry.name == "You"
            )
        }
    }
}
