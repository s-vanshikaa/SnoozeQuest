//
//  LeaderboardView.swift
//  SnoozeQuest
//

import SwiftUI

struct LeaderboardView: View {
    @StateObject private var viewModel = LeaderboardViewModel(leaderboardRepository: AppEnvironment.leaderboardRepository)

    var body: some View {
        NavigationStack {
            content
                .background(SQColor.background)
                .navigationTitle("Leaderboard")
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading leaderboard…")
                .tint(SQColor.moonlight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            SQEmptyState(
                title: "No Rankings Yet",
                systemImage: "list.number",
                message: "Check back once this week's sleep data comes in."
            )

        case .error(let message):
            SQEmptyState(
                title: "Something Went Wrong",
                systemImage: "exclamationmark.triangle",
                message: message
            )

        case .loaded(let entries):
            ScrollView {
                VStack(spacing: SQSpacing.xxl) {
                    SQSectionHeader(title: "Weekly Leaders")
                    podium(entries)
                    remainingList(entries)
                }
                .padding(.horizontal, SQSpacing.screenHorizontal)
                .padding(.vertical, SQSpacing.xl)
            }
        }
    }

    @ViewBuilder
    private func podium(_ entries: [LeaderboardEntry]) -> some View {
        let top3 = Array(entries.prefix(3))

        VStack(spacing: SQSpacing.lg) {
            if let first = top3.first {
                podiumEntry(first, avatarSize: 72, isFirst: true)
            }

            if top3.count > 1 {
                HStack(alignment: .top, spacing: SQSpacing.xxxl) {
                    podiumEntry(top3[1], avatarSize: 56, isFirst: false)
                    if top3.count > 2 {
                        podiumEntry(top3[2], avatarSize: 56, isFirst: false)
                    }
                }
            }
        }
    }

    private func podiumEntry(_ entry: LeaderboardEntry, avatarSize: CGFloat, isFirst: Bool) -> some View {
        VStack(spacing: SQSpacing.xs) {
            if isFirst {
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundStyle(SQColor.moonlight)
                    .accessibilityHidden(true)
            }

            avatar(for: entry, size: avatarSize)
                .accessibilityHidden(true)

            HStack(spacing: 4) {
                Text(entry.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SQColor.textPrimary)
                if entry.isCurrentUser {
                    Text("YOU")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SQColor.moonlight)
                }
            }

            Text("\(entry.averageSleepScore)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(SQColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(podiumAccessibilityLabel(entry, isFirst: isFirst))
    }

    private func podiumAccessibilityLabel(_ entry: LeaderboardEntry, isFirst: Bool) -> String {
        let rankText = isFirst ? "Rank 1" : "Rank \(entry.rank)"
        let name = entry.isCurrentUser ? "\(entry.displayName), you" : entry.displayName
        return "\(rankText), \(name), score \(entry.averageSleepScore)"
    }

    private func remainingList(_ entries: [LeaderboardEntry]) -> some View {
        let rest = Array(entries.dropFirst(3))

        return VStack(spacing: 0) {
            ForEach(Array(rest.enumerated()), id: \.element.id) { index, entry in
                row(for: entry)
                if index < rest.count - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private func row(for entry: LeaderboardEntry) -> some View {
        HStack(spacing: SQSpacing.md) {
            Text("\(entry.rank)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SQColor.textSecondary)
                .frame(minWidth: 22, alignment: .leading)
                .accessibilityHidden(true)

            avatar(for: entry, size: 32)
                .accessibilityHidden(true)

            HStack(spacing: 4) {
                Text(entry.displayName)
                    .font(.subheadline.weight(entry.isCurrentUser ? .bold : .regular))
                    .foregroundStyle(SQColor.textPrimary)
                if entry.isCurrentUser {
                    Text("YOU")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SQColor.moonlight)
                }
            }
            .accessibilityHidden(true)

            Spacer()

            Text("\(entry.averageSleepScore)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(SQColor.textPrimary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, SQSpacing.sm)
        .background(entry.isCurrentUser ? SQColor.moonlight.opacity(0.08) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(podiumAccessibilityLabel(entry, isFirst: false))
    }

    private func avatar(for entry: LeaderboardEntry, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(entry.isCurrentUser ? SQColor.moonlight.opacity(0.22) : SQColor.skyBlue.opacity(0.16))
            Text(initials(for: entry.displayName))
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(entry.isCurrentUser ? SQColor.moonlight : SQColor.skyBlue)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().strokeBorder(entry.isCurrentUser ? SQColor.moonlight : Color.clear, lineWidth: 2)
        )
    }

    private func initials(for name: String) -> String {
        let letters = name.split(separator: " ").compactMap { $0.first }
        return String(letters.prefix(2)).uppercased()
    }
}

#Preview("Loaded") {
    LeaderboardView()
}

#Preview("Empty") {
    LeaderboardPreviewContainer(state: .empty)
}

#Preview("Error") {
    LeaderboardPreviewContainer(state: .error("We couldn't load the leaderboard. Pull to refresh to try again."))
}

private struct LeaderboardPreviewContainer: View {
    let state: LeaderboardViewModel.State

    var body: some View {
        LeaderboardView(previewState: state)
    }
}

private extension LeaderboardView {
    init(previewState: LeaderboardViewModel.State) {
        self.init()
        _viewModel = StateObject(wrappedValue: LeaderboardViewModel(previewState: previewState))
    }
}
