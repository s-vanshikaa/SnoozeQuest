//
//  Primitives.swift
//  SnoozeQuest
//
//  Small, genuinely-reused building blocks.
//

import SwiftUI

/// Uppercase section label (e.g. "LAST NIGHT").
struct SQSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.sqSectionLabel)
            .tracking(0.6)
            .foregroundStyle(SQColor.textSecondary)
    }
}

/// Compact rounded metric chip, e.g. "8h 21m" or "+24m".
struct SQMetricPill: View {
    let text: String
    var tint: Color = SQColor.skyBlue

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, SQSpacing.sm + 2)
            .padding(.vertical, SQSpacing.xs)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

/// A labeled dot + stage name, used in legends.
struct SQSleepStageBadge: View {
    let stage: SleepStage
    var detail: String?

    var body: some View {
        HStack(spacing: SQSpacing.xs) {
            Circle()
                .fill(SQColor.stage(stage))
                .frame(width: 8, height: 8)
            Text(stageName + (detail.map { " \($0)" } ?? ""))
                .font(.caption2)
                .foregroundStyle(SQColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var stageName: String {
        switch stage {
        case .deep: return "Deep"
        case .rem: return "REM"
        case .core: return "Core"
        case .awake: return "Awake"
        }
    }
}

/// Horizontal capsule progress bar — used for the Journey card and other linear progress.
struct SQProgressBar: View {
    var progress: Double
    var tint: Color = SQColor.skyBlue
    var height: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(SQColor.textTertiary.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * animatedProgress)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(SQMotion.interactive(reduceMotion: reduceMotion)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(SQMotion.interactive(reduceMotion: reduceMotion)) {
                animatedProgress = newValue
            }
        }
    }
}

/// Consistent empty/error placeholder built on the design tokens.
struct SQEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: SQSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(SQColor.textSecondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(SQColor.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(SQColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(SQSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
