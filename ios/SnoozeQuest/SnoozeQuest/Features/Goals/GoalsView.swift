//
//  GoalsView.swift
//  SnoozeQuest
//

import SwiftUI

struct GoalsView: View {
    @StateObject private var viewModel = GoalsViewModel()

    var body: some View {
        NavigationStack {
            content
                .background(SQColor.background)
                .navigationTitle("Goals")
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
                .alert("Goal Saved", isPresented: $viewModel.didSave) {
                    Button("OK", role: .cancel) {}
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Loading your goal…")
                .tint(SQColor.moonlight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let message):
            SQEmptyState(
                title: "Something Went Wrong",
                systemImage: "exclamationmark.triangle",
                message: message
            )

        case .loaded(let goals):
            ScrollView {
                VStack(spacing: SQSpacing.xxl) {
                    streakSection(goals)
                    tonightSection()
                    scheduleSection()

                    if let nextWorldText = goals.nextWorldText {
                        nextWorldSection(nextWorldText)
                    }

                    if let message = viewModel.validationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(SQColor.error)
                    }

                    Button {
                        Task { await viewModel.save() }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("Save Goal")
                        }
                    }
                    .buttonStyle(.sqPrimary)
                    .disabled(viewModel.isSaving)
                }
                .padding(.horizontal, SQSpacing.screenHorizontal)
                .padding(.vertical, SQSpacing.lg)
            }
        }
    }

    private func streakSection(_ goals: GoalsDisplayModel) -> some View {
        VStack(spacing: SQSpacing.md) {
            SQSectionHeader(title: "\(goals.streakCount) day streak")

            HStack(spacing: SQSpacing.sm) {
                ForEach(0..<7, id: \.self) { index in
                    Circle()
                        .fill(index < min(goals.streakCount, 7) ? SQColor.moonlight : SQColor.textTertiary.opacity(0.25))
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(min(goals.streakCount, 7)) of 7 days on goal")

            Text("\(goals.completionPercentageText) of the last 30 nights on goal")
                .font(.caption)
                .foregroundStyle(SQColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tonightSection() -> some View {
        VStack(spacing: SQSpacing.md) {
            SQSectionHeader(title: "Tonight")
            SQDurationSlider(duration: $viewModel.targetDuration)
        }
    }

    private func scheduleSection() -> some View {
        HStack(spacing: SQSpacing.xxxl) {
            scheduleField(title: "Bedtime", selection: $viewModel.bedtime)
            scheduleField(title: "Wake", selection: $viewModel.wakeTime)
        }
    }

    private func scheduleField(title: String, selection: Binding<Date>) -> some View {
        VStack(spacing: SQSpacing.xs) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SQColor.textSecondary)
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(SQColor.moonlight)
        }
    }

    private func nextWorldSection(_ text: String) -> some View {
        VStack(spacing: SQSpacing.xs) {
            SQSectionHeader(title: "Next World")
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SQColor.textPrimary)
        }
    }
}

#Preview("Loaded") {
    GoalsView()
}

#Preview("Error") {
    GoalsPreviewContainer(state: .error("We couldn't load your goal. Pull to refresh to try again."))
}

private struct GoalsPreviewContainer: View {
    let state: GoalsViewModel.State

    var body: some View {
        GoalsView(previewState: state)
    }
}

private extension GoalsView {
    init(previewState: GoalsViewModel.State) {
        self.init()
        _viewModel = StateObject(wrappedValue: GoalsViewModel(previewState: previewState))
    }
}
