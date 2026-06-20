//
//  SQCosmicHero.swift
//  SnoozeQuest
//
//  Dashboard's cosmic sleep-score hero: the Sleep Moon set inside a small
//  animated universe — starfield, faint orbit rings, and nearby worlds —
//  echoing the Journey solar-system metaphor rather than a flat score card.
//

import SwiftUI

struct SQCosmicHero: View {
    var progress: Double
    var value: String
    var label: String
    var size: CGFloat = 220

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var outerRingRotation: Double = 0
    @State private var worldsRotation: Double = 0

    private struct NearbyWorld {
        let radiusScale: CGFloat
        let angleDegrees: Double
        let diameter: CGFloat
        let colors: [Color]
    }

    /// A restrained echo of the Journey worlds (Mars, Earth, a distant moon) — not literal milestones.
    /// radiusScale/diameterScale are fractions of `size`, keeping the whole composition proportional
    /// and safely narrower than the moon's own unclipped halo bleed, so it never overflows the screen.
    private static let worlds: [NearbyWorld] = [
        NearbyWorld(
            radiusScale: 0.49,
            angleDegrees: -35,
            diameter: 14,
            colors: [Color(red: 0.80, green: 0.44, blue: 0.32), Color(red: 0.55, green: 0.25, blue: 0.17)]
        ),
        NearbyWorld(
            radiusScale: 0.59,
            angleDegrees: 150,
            diameter: 10,
            colors: [Color(red: 0.30, green: 0.58, blue: 0.85), Color(red: 0.16, green: 0.36, blue: 0.56)]
        ),
        NearbyWorld(
            radiusScale: 0.645,
            angleDegrees: 55,
            diameter: 6,
            colors: [SQColor.skyBlue, SQColor.skyBlue.opacity(0.5)]
        )
    ]

    /// Bounding frame for the whole composition. Kept close to the moon's own halo bleed (1.4x)
    /// so the hero never grows wider than existing SQSleepMoon usage elsewhere in the app.
    private var fieldSize: CGFloat { size * 1.36 }

    var body: some View {
        ZStack {
            SQStarfield(starCount: 36, twinkles: true)
                .frame(width: fieldSize, height: fieldSize)

            orbitRing(scale: 1.34, dashed: false)
            orbitRing(scale: 1.62, dashed: true)
                .rotationEffect(.degrees(outerRingRotation))

            ForEach(Array(Self.worlds.enumerated()), id: \.offset) { _, world in
                nearbyWorld(world)
                    .frame(width: fieldSize, height: fieldSize)
                    .rotationEffect(.degrees(world.angleDegrees + worldsRotation))
            }

            SQSleepMoon(progress: progress, value: value, label: label, size: size)
        }
        .frame(width: fieldSize, height: fieldSize)
        .scaleEffect(hasAppeared ? 1 : 0.86)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear(perform: animateIn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func orbitRing(scale: CGFloat, dashed: Bool) -> some View {
        Circle()
            .strokeBorder(
                SQColor.textPrimary.opacity(0.09),
                style: StrokeStyle(lineWidth: 1, dash: dashed ? [1, 7] : [])
            )
            .frame(width: size * scale, height: size * scale)
            .allowsHitTesting(false)
    }

    private func nearbyWorld(_ world: NearbyWorld) -> some View {
        Circle()
            .fill(LinearGradient(colors: world.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: world.diameter, height: world.diameter)
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: world.colors[0].opacity(0.35), radius: 3)
            .offset(y: -size * world.radiusScale)
            .allowsHitTesting(false)
    }

    private func animateIn() {
        withAnimation(SQMotion.transition(reduceMotion: reduceMotion)) {
            hasAppeared = true
        }

        guard !reduceMotion else { return }

        withAnimation(.linear(duration: 200).repeatForever(autoreverses: false)) {
            outerRingRotation = 360
        }
        withAnimation(.linear(duration: 130).repeatForever(autoreverses: false)) {
            worldsRotation = 360
        }
    }
}

#Preview("Cosmic Hero") {
    ZStack {
        SQColor.background.ignoresSafeArea()
        SQCosmicHero(progress: 0.84, value: "84", label: "Sleep Score", size: 220)
    }
}
