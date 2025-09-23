//
//  SQSleepMoon.swift
//  SnoozeQuest
//
//  SnoozeQuest's signature visual motif — used sparingly: Welcome screen and the
//  Dashboard Sleep Score hero. Progress reads as illumination rising over the
//  moon's disc rather than a generic progress ring.
//

import SwiftUI

struct SQSleepMoon: View {
    var progress: Double?
    var value: String?
    var label: String?
    var size: CGFloat = 200
    var breathes: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0
    @State private var isBreathing = false

    private static let craters: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (0.30, 0.34, 0.11),
        (0.62, 0.24, 0.07),
        (0.68, 0.60, 0.13),
        (0.28, 0.68, 0.06)
    ]

    var body: some View {
        ZStack {
            // Restrained ambient halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [SQColor.moonlight.opacity(0.22), .clear],
                        center: .center,
                        startRadius: size * 0.1,
                        endRadius: size * 0.7
                    )
                )
                .frame(width: size * 1.4, height: size * 1.4)
                .blur(radius: 18)
                .allowsHitTesting(false)

            // Moon disc: dim base + rising illumination, clipped to the disc only
            // (the halo above must stay unclipped so its blur can bleed outward).
            ZStack {
                Circle()
                    .fill(SQColor.surfaceDeep)
                    .overlay(craterTexture.opacity(0.5))

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [SQColor.moonlight, SQColor.moonlight.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(craterTexture.opacity(0.18))
                    .mask(
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle().frame(height: size * animatedProgress)
                        }
                    )
                    .opacity(progress == nil ? 0.9 : 1)

                Circle()
                    .strokeBorder(SQColor.moonlight.opacity(0.35), lineWidth: 1.5)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if let value {
                VStack(spacing: 4) {
                    Text(value)
                        .font(.sqMetricHero)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .foregroundStyle(SQColor.textPrimary)

                    if let label {
                        Text(label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SQColor.textSecondary)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(isBreathing ? 1.012 : 1.0)
        .onAppear {
            if let progress {
                withAnimation(reduceMotion ? .easeInOut(duration: SQMotion.standard) : .spring(response: 0.9, dampingFraction: 0.82)) {
                    animatedProgress = progress
                }
            } else {
                animatedProgress = 0.55
            }
            if breathes && !reduceMotion {
                withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true).delay(0.6)) {
                    isBreathing = true
                }
            }
        }
        .onChange(of: progress) { _, newValue in
            guard let newValue else { return }
            withAnimation(SQMotion.interactive(reduceMotion: reduceMotion)) {
                animatedProgress = newValue
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Sleep moon")
        .accessibilityValue(value ?? "")
    }

    private var craterTexture: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(Self.craters.enumerated()), id: \.offset) { _, crater in
                    Circle()
                        .fill(SQColor.background.opacity(0.4))
                        .frame(width: geometry.size.width * crater.r)
                        .position(x: geometry.size.width * crater.x, y: geometry.size.height * crater.y)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview("Halo + Fill") {
    ZStack {
        SQColor.background.ignoresSafeArea()
        SQSleepMoon(progress: 0.84, value: "84", label: "Sleep Score", size: 220)
    }
}
