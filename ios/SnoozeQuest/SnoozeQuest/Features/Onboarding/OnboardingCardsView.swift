//
//  OnboardingCardsView.swift
//  SnoozeQuest
//

import SwiftUI

private struct OnboardingCardContent: Identifiable {
    let id: Int
    let headline: String
    let bullets: [String]
}

private let onboardingCards: [OnboardingCardContent] = [
    OnboardingCardContent(
        id: 0,
        headline: "See the whole night.",
        bullets: ["Duration", "Stages", "Score", "Trends"]
    ),
    OnboardingCardContent(
        id: 1,
        headline: "Consistency beats perfection.",
        bullets: ["Goals", "Streaks", "Consistency"]
    ),
    OnboardingCardContent(
        id: 2,
        headline: "Turn progress into worlds.",
        bullets: ["Consistent sleep moves your SnoozeQuest forward."]
    )
]

struct OnboardingCardsView: View {
    @Binding var cardIndex: Int
    var onContinue: () -> Void
    var onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition: Int?

    var body: some View {
        VStack(spacing: SQSpacing.xl) {
            HStack {
                Spacer()
                Button("Skip", action: onSkip)
                    .foregroundStyle(SQColor.textSecondary)
            }
            .padding(.horizontal, SQSpacing.screenHorizontal)

            ScrollView(.horizontal) {
                HStack(spacing: SQSpacing.base) {
                    ForEach(onboardingCards) { card in
                        OnboardingCardView(index: card.id, content: card)
                            .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: SQSpacing.base)
                            .id(card.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, SQSpacing.screenHorizontal)
                .padding(.vertical, SQSpacing.sm)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollPosition)
            .scrollIndicators(.hidden)
            .onChange(of: scrollPosition) { _, newValue in
                if let newValue { cardIndex = newValue }
            }
            .onAppear { scrollPosition = cardIndex }

            pageIndicator

            Button(cardIndex == onboardingCards.count - 1 ? "Continue" : "Next") {
                advance()
            }
            .buttonStyle(.sqPrimary)
            .padding(.horizontal, SQSpacing.screenHorizontal)
        }
        .padding(.vertical, SQSpacing.xl)
        .background(SQColor.background)
    }

    private var pageIndicator: some View {
        HStack(spacing: SQSpacing.sm) {
            ForEach(onboardingCards) { card in
                let isActive = card.id == cardIndex
                Capsule()
                    .fill(isActive ? SQColor.moonlight : SQColor.textTertiary.opacity(0.3))
                    .frame(width: isActive ? 18 : 6, height: 6)
            }
        }
        .animation(SQMotion.interactive(reduceMotion: reduceMotion), value: cardIndex)
    }

    private func advance() {
        if cardIndex == onboardingCards.count - 1 {
            onContinue()
        } else {
            let next = cardIndex + 1
            withAnimation(SQMotion.interactive(reduceMotion: reduceMotion)) {
                scrollPosition = next
            }
            cardIndex = next
        }
    }
}

private struct OnboardingCardView: View {
    let index: Int
    let content: OnboardingCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: SQSpacing.lg) {
            illustration
                .frame(height: 120)

            Text(content.headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(SQColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: SQSpacing.xs) {
                ForEach(content.bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: SQSpacing.sm) {
                        Circle()
                            .fill(SQColor.moonlight)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(bullet)
                            .font(.subheadline)
                            .foregroundStyle(SQColor.textSecondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(SQSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SQRadius.card + 4, style: .continuous)
                .fill(SQColor.surface)
        )
    }

    @ViewBuilder
    private var illustration: some View {
        switch index {
        case 0: MiniSleepTimeline()
        case 1: MiniWeekProgress()
        default: MiniJourneyPreview()
        }
    }
}

private struct MiniSleepTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private let segments: [(SleepStage, CGFloat)] = [
        (.awake, 0.05), (.core, 0.35), (.deep, 0.25), (.rem, 0.2), (.core, 0.15)
    ]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(SQColor.stage(segment.0))
                        .frame(width: geometry.size.width * segment.1)
                }
            }
            .frame(width: geometry.size.width * (revealed ? 1 : 0.05), alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 28)
        .frame(maxHeight: .infinity)
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.easeOut(duration: 0.9)) { revealed = true }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MiniWeekProgress: View {
    private let heights: [CGFloat] = [0.5, 0.75, 0.6, 0.9, 0.4, 0.85, 1.0]

    var body: some View {
        HStack(alignment: .bottom, spacing: SQSpacing.sm) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                let isLast = index == heights.count - 1
                RoundedRectangle(cornerRadius: 3)
                    .fill(isLast ? AnyShapeStyle(SQColor.moonlight) : AnyShapeStyle(SQColor.skyBlue.opacity(0.4)))
                    .frame(width: 10, height: 70 * height)
            }

            Spacer()

            SQProgressRing(progress: 0.75, lineWidth: 6, tint: SQColor.moonlight)
                .frame(width: 56, height: 56)
                .overlay(
                    Text("75%")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SQColor.textPrimary)
                )
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

private struct MiniJourneyPreview: View {
    private let worlds: [WorldDisplay] = [
        WorldDisplay(id: 0, name: "Earth", state: .unlocked, requiredGoalNights: 0),
        WorldDisplay(id: 1, name: "Mars", state: .current, requiredGoalNights: 4),
        WorldDisplay(id: 2, name: "Venus", state: .locked, requiredGoalNights: 9)
    ]

    var body: some View {
        HStack(spacing: SQSpacing.lg) {
            ForEach(worlds) { world in
                SQPlanet(world: world, size: 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingCardsView(cardIndex: .constant(0), onContinue: {}, onSkip: {})
        .background(SQColor.background)
}
