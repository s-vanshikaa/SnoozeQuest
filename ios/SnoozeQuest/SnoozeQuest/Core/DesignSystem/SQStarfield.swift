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
    /// When true, a small subset of stars gently pulse opacity (respects Reduce Motion).
    var twinkles: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var twinklePhase = false

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
            ForEach(Array(Self.stars.prefix(starCount).enumerated()), id: \.offset) { index, star in
                Circle()
                    .fill(SQColor.textSecondary.opacity(star.opacity * lightModeDimming))
                    .frame(width: star.size, height: star.size)
                    .position(x: geometry.size.width * star.x, y: geometry.size.height * star.y)
                    .opacity(isTwinkling(index) && twinklePhase ? 0.35 : 1)
                    .animation(
                        isTwinkling(index)
                            ? .easeInOut(duration: 2.2 + Double(index % 3) * 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index % 5) * 0.35)
                            : nil,
                        value: twinklePhase
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard twinkles, !reduceMotion else { return }
            twinklePhase = true
        }
    }

    private func isTwinkling(_ index: Int) -> Bool {
        twinkles && !reduceMotion && index % 6 == 0
    }

    /// Stars are tuned for dark backdrops; soften them on light backgrounds so they
    /// read as faint flecks rather than dark specks against a bright surface.
    private var lightModeDimming: Double {
        colorScheme == .light ? 0.45 : 1.0
    }
}
