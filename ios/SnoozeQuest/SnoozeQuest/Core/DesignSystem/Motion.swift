//
//  Motion.swift
//  SnoozeQuest
//
//  Reusable motion constants. Prefer these over inventing timing per screen.
//  Every call site should branch on accessibilityReduceMotion using the helpers below.
//

import SwiftUI

enum SQMotion {
    static let fast: Double = 0.16
    static let standard: Double = 0.28
    static let staggerDelay: Double = 0.06

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let gentleSpring = Animation.spring(response: 0.55, dampingFraction: 0.86)

    /// A spring for interactive settling (cards, rings, sheets); falls back to a quick fade under Reduce Motion.
    static func interactive(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: fast) : spring
    }

    /// A gentle transition for content entering/leaving (fades, loading, screen entrances).
    static func transition(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? fast : standard)
    }
}
