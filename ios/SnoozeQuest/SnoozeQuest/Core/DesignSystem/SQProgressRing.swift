//
//  SQProgressRing.swift
//  SnoozeQuest
//

import SwiftUI

/// A compact progress ring for secondary metrics (goal progress, completion percentage,
/// Journey progress). For the primary Sleep Score hero, use SQSleepMoon instead.
struct SQProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = SQColor.skyBlue

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(SQColor.textSecondary.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
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
