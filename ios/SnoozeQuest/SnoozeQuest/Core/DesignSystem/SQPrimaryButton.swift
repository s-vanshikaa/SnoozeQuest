//
//  SQPrimaryButton.swift
//  SnoozeQuest
//

import SwiftUI

struct SQPrimaryButtonStyle: ButtonStyle {
    var isProminent: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isProminent ? Color.white : SQColor.skyBlue)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(isProminent ? SQColor.skyBlue : SQColor.skyBlue.opacity(0.14))
            .overlay(
                // subtle top highlight for tactility, not a decorative gradient
                LinearGradient(colors: [.white.opacity(isProminent ? 0.12 : 0), .clear], startPoint: .top, endPoint: .bottom)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .clipShape(RoundedRectangle(cornerRadius: SQRadius.button, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(SQMotion.interactive(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SQPrimaryButtonStyle {
    static var sqPrimary: SQPrimaryButtonStyle { SQPrimaryButtonStyle(isProminent: true) }
    static var sqSecondary: SQPrimaryButtonStyle { SQPrimaryButtonStyle(isProminent: false) }
}
