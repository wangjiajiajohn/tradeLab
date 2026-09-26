import SwiftUI

struct FirstBacktestFlowView: View {
    private enum Stage: Int, CaseIterable {
        case intro
        case stock
        case strategy
        case settings
        case run

        var progressIndex: Int? {
            self == .intro ? nil : rawValue
        }
    }

    @EnvironmentObject private var model: AppModel
    @State private var stage: Stage = .intro

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let progress = stage.progressIndex {
                    StepProgressView(currentStep: progress)
                        .padding(.horizontal)
                        .padding(.top, 12)
                }

                ScrollView {
                    Group {
                        switch stage {
                        case .intro: intro
                        case .stock: stockStep
                        case .strategy: strategyStep
                        case .settings: settingsStep
                        case .run: runStep
                        }
                    }
                    .id(stage)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                    .padding(24)
                }
            }
            .toolbar {
                if stage != .intro && stage != .stock {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("action.back") { moveBackward() }
                    }
                }
            }
            .alert("error.title", isPresented: errorPresented) {
                Button("action.ok", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var intro: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 54)
            introSymbol
            Text("onboarding.question")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("onboarding.answer")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 42)
            Button("onboarding.start") { move(to: .stock) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            Label("onboarding.offline", systemImage: "wifi.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var introSymbol: some View {
        if #available(iOS 26.0, *) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(.tint)
                .symbolEffect(.drawOn.individually)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
    }

    private var stockStep: some View {
        StepContainer(
            symbol: "chart.line.uptrend.xyaxis",
            title: String(localized: "onboarding.stock.title"),
            subtitle: String(localized: "onboarding.stock.subtitle")
        ) {
            LazyVStack(spacing: 10) {
                ForEach(model.securities) { security in
                    Button {
                        model.selectSecurity(security)
                    } label: {
                        SelectionRow(
                            title: security.name,
                            subtitle: securitySubtitle(security),
                            selected: model.selectedSecurityID == security.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("action.continue") { move(to: .strategy) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedSecurity == nil)
        }
    }

    private var strategyStep: some View {
        StepContainer(
            symbol: "slider.horizontal.3",
            title: String(localized: "onboarding.strategy.title"),
            subtitle: String(localized: "onboarding.strategy.subtitle")
        ) {
            LazyVStack(spacing: 10) {
                ForEach(model.strategies) { strategy in
                    Button {
                        model.selectStrategy(strategy)
                    } label: {
                        SelectionRow(
                            title: strategy.name,
                            subtitle: strategy.summary,
                            selected: model.selectedStrategyID == strategy.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("action.continue") { move(to: .settings) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.selectedStrategy == nil)
        }
    }

    private var settingsStep: some View {
        StepContainer(
            symbol: "calendar.badge.clock",
            title: String(localized: "onboarding.settings.title"),
            subtitle: String(localized: "onboarding.settings.subtitle")
        ) {
            VStack(spacing: 0) {
                LabeledContent("settings.period", value: selectedPeriod)
                Divider()
                LabeledContent(
                    "settings.capital",
                    value: model.settings.initialCapital,
                    format: .currency(code: model.selectedSecurity?.currency ?? "USD")
                )
                Divider()
                LabeledContent("settings.costs", value: "0.10% / 0.05%")
            }
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 16))

            Button("onboarding.settings.confirm") {
                model.hasConfirmedSettings = true
                move(to: .run)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var runStep: some View {
        StepContainer(
            symbol: "play.fill",
            title: String(localized: "onboarding.run.title"),
            subtitle: String(localized: "onboarding.run.subtitle")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ReadyRow(text: model.selectedSecurity?.name ?? "—")
                ReadyRow(text: model.selectedStrategy?.name ?? "—")
                ReadyRow(text: String(localized: "onboarding.run.conditions_ready"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 16))

            Button {
                _ = model.runBacktest(completesOnboarding: true)
            } label: {
                Label("onboarding.run.button", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var selectedPeriod: String {
        guard let first = model.selectedCandles.first?.date,
              let last = model.selectedCandles.last?.date
        else { return "—" }
        return first.formatted(.dateTime.year().month(.abbreviated))
            + " – "
            + last.formatted(.dateTime.year().month(.abbreviated))
    }

    private func securitySubtitle(_ security: Security) -> String {
        let market = security.market == .hk
            ? String(localized: "market.hk")
            : String(localized: "market.us")
        let source = security.isSyntheticDemo
            ? String(localized: "data.synthetic")
            : String(localized: "data.development_offline")
        return "\(security.symbol) · \(market) · \(source)"
    }

    private func move(to next: Stage) {
        withAnimation(.snappy(duration: 0.4)) { stage = next }
    }

    private func moveBackward() {
        guard let previous = Stage(rawValue: stage.rawValue - 1) else { return }
        move(to: previous)
    }
}

private struct StepProgressView: View {
    let currentStep: Int
    private let colors: [Color] = [.blue, .purple, .orange, .green]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(1...4, id: \.self) { step in
                    Capsule()
                        .fill(colors[step - 1].opacity(step <= currentStep ? 1 : 0.18))
                        .frame(height: 5)
                }
            }
            HStack {
                Text(String(format: String(localized: "onboarding.progress_format"), currentStep))
                Spacer()
                Text(stepName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var stepName: LocalizedStringKey {
        switch currentStep {
        case 1: "onboarding.progress.stock"
        case 2: "onboarding.progress.strategy"
        case 3: "onboarding.progress.settings"
        default: "onboarding.progress.run"
        }
    }
}

private struct StepContainer<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            content
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }
}

private struct SelectionRow: View {
    let title: String
    let subtitle: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .font(.title2)
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
    }
}

private struct ReadyRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.primary, .green)
    }
}
