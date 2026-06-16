//
//  SQPlanet.swift
//  SnoozeQuest
//
//  Native-SwiftUI planet visuals for the Journey system. No external assets.
//

import SwiftUI

struct SQPlanet: View {
    let world: WorldDisplay
    var size: CGFloat = 64
    var showsLabel: Bool = true

    var body: some View {
        VStack(spacing: SQSpacing.xs) {
            ZStack {
                if world.state == .current {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [SQColor.moonlight.opacity(0.4), .clear],
                                center: .center,
                                startRadius: size * 0.1,
                                endRadius: size * 0.9
                            )
                        )
                        .frame(width: size * 1.8, height: size * 1.8)
                        .blur(radius: 10)
                }

                if world.name == "Saturn" && world.state != .locked {
                    Ellipse()
                        .stroke(SQColor.textPrimary.opacity(0.32), lineWidth: 3)
                        .frame(width: size * 1.55, height: size * 0.5)
                        .rotationEffect(.degrees(-18))
                }

                Circle()
                    .fill(LinearGradient(colors: planetColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size, height: size)
                    .saturation(world.state == .locked ? 0.2 : 1)
                    .opacity(world.state == .locked ? 0.5 : 1)
                    .overlay(
                        Circle().strokeBorder(world.state == .current ? SQColor.moonlight : .clear, lineWidth: 2)
                    )

                if world.state == .locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.26))
                        .foregroundStyle(SQColor.textSecondary)
                }
            }
            .frame(width: size * 1.8, height: size * 1.8)
            .scaleEffect(world.state == .current ? 1.08 : 1.0)

            if showsLabel {
                Text(world.name)
                    .font(.caption.weight(world.state == .current ? .bold : .medium))
                    .foregroundStyle(world.state == .locked ? SQColor.textTertiary : SQColor.textPrimary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var planetColors: [Color] {
        switch world.name {
        case "Earth": return [Color(red: 0.30, green: 0.58, blue: 0.85), Color(red: 0.16, green: 0.36, blue: 0.56)]
        case "Mars": return [Color(red: 0.80, green: 0.44, blue: 0.32), Color(red: 0.55, green: 0.25, blue: 0.17)]
        case "Venus": return [Color(red: 0.88, green: 0.76, blue: 0.54), Color(red: 0.66, green: 0.53, blue: 0.33)]
        case "Saturn": return [Color(red: 0.85, green: 0.75, blue: 0.56), Color(red: 0.63, green: 0.51, blue: 0.35)]
        case "Jupiter": return [Color(red: 0.79, green: 0.61, blue: 0.43), Color(red: 0.56, green: 0.39, blue: 0.25)]
        case "Neptune": return [Color(red: 0.31, green: 0.41, blue: 0.79), Color(red: 0.17, green: 0.23, blue: 0.53)]
        default: return [SQColor.skyBlue, SQColor.skyBlue.opacity(0.6)]
        }
    }

    private var accessibilityLabel: String {
        switch world.state {
        case .unlocked: return "\(world.name), unlocked"
        case .current: return "\(world.name), current world"
        case .locked: return "\(world.name), locked, unlocks after \(world.requiredGoalNights) goal nights"
        }
    }
}
