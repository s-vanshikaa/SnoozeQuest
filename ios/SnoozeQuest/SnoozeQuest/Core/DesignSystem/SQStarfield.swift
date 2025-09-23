//
//  SQStarfield.swift
//  SnoozeQuest
//
//  Restrained, static depth cue for immersive/hero backdrops (Welcome, Journey).
//  Deterministic and cheap: fixed positions, no per-frame recomputation.
//

import SwiftUI

struct SQStarfield: View {
    var starCount: Int = 60

    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = {
        var generator = SeededGenerator(seed: 99)
        return (0..<90).map { _ in
            (
                x: CGFloat.random(in: 0...1, using: &generator),
                y: CGFloat.random(in: 0...1, using: &generator),
                size: CGFloat.random(in: 1...2.2, using: &generator),
                opacity: Double.random(in: 0.2...0.85, using: &generator)
            )
        }
    }()

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(Self.stars.prefix(starCount).enumerated()), id: \.offset) { _, star in
                Circle()
                    .fill(SQColor.textPrimary.opacity(star.opacity))
                    .frame(width: star.size, height: star.size)
                    .position(x: geometry.size.width * star.x, y: geometry.size.height * star.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
