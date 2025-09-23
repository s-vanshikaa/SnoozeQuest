//
//  Typography.swift
//  SnoozeQuest
//
//  Apple system fonts only. Rounded design for brand/metrics, standard design for UI text.
//

import SwiftUI

extension Font {
    /// Brand wordmark / onboarding headlines.
    static var sqBrandTitle: Font { .system(.largeTitle, design: .rounded, weight: .bold) }

    /// Sleep Score and other hero metrics.
    static var sqMetricHero: Font { .system(size: 56, weight: .bold, design: .rounded) }

    /// Primary sleep duration and other large-but-secondary metrics.
    static var sqMetricLarge: Font { .system(.title, design: .rounded, weight: .semibold) }

    /// Screen-level headings.
    static var sqScreenTitle: Font { .system(.title2, design: .default, weight: .bold) }

    /// Section labels (e.g. "LAST NIGHT").
    static var sqSectionLabel: Font { .system(.caption, design: .default, weight: .semibold) }
}
