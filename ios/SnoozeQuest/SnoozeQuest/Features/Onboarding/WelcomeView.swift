//
//  WelcomeView.swift
//  SnoozeQuest
//

import SwiftUI

struct WelcomeView: View {
    var onGetStarted: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showStars = false
    @State private var showMoon = false
    @State private var showWordmark = false
    @State private var showHeadline = false
    @State private var showBody = false
    @State private var showCTA = false

    var body: some View {
        ZStack {
            SQColor.surfaceDeep.ignoresSafeArea()

            SQStarfield()
                .opacity(showStars ? 1 : 0)
                .ignoresSafeArea()

            VStack(spacing: SQSpacing.xxl) {
                Spacer()

                SQSleepMoon(size: 140, breathes: true)
                    .opacity(showMoon ? 1 : 0)
                    .scaleEffect(showMoon ? 1 : 0.8)

                VStack(spacing: SQSpacing.md) {
                    Text("SNOOZEQUEST")
                        .font(.sqBrandTitle)
                        .tracking(2)
                        .foregroundStyle(SQColor.textPrimary)
                        .opacity(showWordmark ? 1 : 0)
                        .blur(radius: showWordmark ? 0 : 8)

                    VStack(spacing: SQSpacing.sm) {
                        Text("Turn better nights\ninto new worlds.")
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(SQColor.textPrimary)
                            .opacity(showHeadline ? 1 : 0)
                            .offset(y: showHeadline ? 0 : 12)

                        Text("Build your rhythm. Track your progress.\nUnlock your journey.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(SQColor.textSecondary)
                            .padding(.horizontal, SQSpacing.xl)
                            .opacity(showBody ? 1 : 0)
                            .offset(y: showBody ? 0 : 12)
                    }
                }

                Spacer()

                Button("Get Started", action: onGetStarted)
                    .buttonStyle(.sqPrimary)
                    .padding(.horizontal, SQSpacing.screenHorizontal)
                    .opacity(showCTA ? 1 : 0)
                    .offset(y: showCTA ? 0 : 12)
            }
            .padding(.vertical, SQSpacing.xxl)
        }
        .onAppear { runEntranceSequence() }
    }

    private func runEntranceSequence() {
        guard !reduceMotion else {
            showStars = true
            showMoon = true
            showWordmark = true
            showHeadline = true
            showBody = true
            showCTA = true
            return
        }

        withAnimation(.easeOut(duration: SQMotion.standard)) { showStars = true }
        withAnimation(SQMotion.gentleSpring.delay(SQMotion.staggerDelay * 2)) { showMoon = true }
        withAnimation(.easeOut(duration: SQMotion.standard).delay(SQMotion.staggerDelay * 5)) { showWordmark = true }
        withAnimation(.easeOut(duration: SQMotion.standard).delay(SQMotion.staggerDelay * 8)) { showHeadline = true }
        withAnimation(.easeOut(duration: SQMotion.standard).delay(SQMotion.staggerDelay * 10)) { showBody = true }
        withAnimation(.easeOut(duration: SQMotion.standard).delay(SQMotion.staggerDelay * 12)) { showCTA = true }
    }
}

#Preview {
    WelcomeView(onGetStarted: {})
}
