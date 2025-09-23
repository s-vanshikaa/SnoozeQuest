//
//  Theme.swift
//  SnoozeQuest
//
//  Cosmic Sleep Journey semantic design tokens. Feature Views should reference
//  these instead of raw colors.
//

import SwiftUI

enum SQColor {
    /// Base screen background (Night / light Background).
    static let background = Color("SQBackground")
    /// Card and sheet surfaces (Elevated Night / light Surface).
    static let surface = Color("SQSurface")
    /// Hero/immersive backdrops — Welcome, Journey (Deep Night / light Elevated Surface).
    static let surfaceDeep = Color("SQSurfaceDeep")

    /// Analytics, controls, navigation selections, secondary progress.
    static let skyBlue = Color("SQSkyBlue")
    /// The signature SnoozeQuest accent. Reserved for the moon, achievements,
    /// major score highlights, and important progress — never every button.
    static let moonlight = Color("SQMoonlight")

    static let success = Color("SQSuccess")
    static let warning = Color("SQWarning")
    static let error = Color("SQError")

    static let textPrimary = Color("SQTextPrimary")
    static let textSecondary = Color("SQTextSecondary")
    static let textTertiary = Color("SQTextTertiary")

    /// Fixed sleep-stage colors — a separate, stable vocabulary from Journey/planet colors.
    static func stage(_ stage: SleepStage) -> Color {
        switch stage {
        case .deep: return Color("SQStageDeep")
        case .rem: return Color("SQStageREM")
        case .core: return Color("SQStageCore")
        case .awake: return Color("SQStageAwake")
        }
    }
}

enum SQSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let base: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 48

    /// Default horizontal content padding.
    static let screenHorizontal: CGFloat = 20
}

enum SQRadius {
    static let card: CGFloat = 22
    static let button: CGFloat = 17
    static let pill: CGFloat = 999
}
