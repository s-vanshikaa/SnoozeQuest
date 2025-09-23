//
//  JourneyView.swift
//  SnoozeQuest
//

import SwiftUI

struct JourneyView: View {
    @StateObject private var viewModel = JourneyViewModel()
    @State private var selectedWorld: WorldDisplay?

    var body: some View {
        ZStack {
            SQColor.surfaceDeep.ignoresSafeArea()
            SQStarfield(starCount: 36).ignoresSafeArea()

            content
        }
        .navigationTitle("Your Journey")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(item: $selectedWorld) { world in
            PlanetDetailView(detail: viewModel.milestoneDetail(for: world))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Charting your journey…")
                .tint(SQColor.moonlight)

        case .error(let message):
            SQEmptyState(title: "Something Went Wrong", systemImage: "sparkle", message: message)

        case .loaded(let journey):
            ScrollView {
                VStack(spacing: SQSpacing.xxxl) {
                    currentWorldSpotlight(journey)
                    JourneyPathView(worlds: journey.worlds) { world in
                        SQHaptics.selectionChanged()
                        selectedWorld = world
                    }
                }
                .padding(.horizontal, SQSpacing.screenHorizontal)
                .padding(.vertical, SQSpacing.xl)
            }
        }
    }

    private func currentWorldSpotlight(_ journey: JourneyDisplayModel) -> some View {
        VStack(spacing: SQSpacing.md) {
            SQPlanet(world: journey.currentWorld, size: 96, showsLabel: false)

            Text(journey.currentWorld.name)
                .font(.sqMetricLarge)
                .foregroundStyle(SQColor.textPrimary)

            if let nextWorldName = journey.nextWorldName, let remaining = journey.goalNightsUntilNext {
                Text("\(remaining) goal night\(remaining == 1 ? "" : "s") until \(nextWorldName)")
                    .font(.subheadline)
                    .foregroundStyle(SQColor.textSecondary)

                SQProgressBar(progress: journey.progressToNextWorld, tint: SQColor.moonlight)
                    .frame(width: 220)
            } else {
                Text("You've explored every world. More are on the way.")
                    .font(.subheadline)
                    .foregroundStyle(SQColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct JourneyPathView: View {
    let worlds: [WorldDisplay]
    let onSelect: (WorldDisplay) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(SQColor.textTertiary.opacity(0.22))
                .frame(width: 2)
                .padding(.vertical, 44)

            VStack(spacing: SQSpacing.xxl) {
                ForEach(Array(worlds.enumerated()), id: \.element.id) { index, world in
                    HStack {
                        if index.isMultiple(of: 2) == false { Spacer() }

                        Button {
                            guard world.state != .locked else { return }
                            onSelect(world)
                        } label: {
                            SQPlanet(world: world, size: 52)
                        }
                        .buttonStyle(.plain)
                        .disabled(world.state == .locked)

                        if index.isMultiple(of: 2) { Spacer() }
                    }
                }
            }
        }
    }
}

#Preview("Loaded") {
    NavigationStack {
        JourneyView()
    }
}
