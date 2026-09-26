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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: Stage = .intro

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if let progress = stage.progressIndex {
                        StepProgressView(currentStep: progress)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
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
                        .padding(.horizontal, 20)
                        .padding(.top, stage == .intro ? 20 : 22)
                        .padding(.bottom, stage == .intro ? 24 : 104)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if stage != .intro {
                    primaryAction
                }
            }
            .tint(stageTint)
            .animation(.easeInOut(duration: 0.25), value: stage)
            .toolbar {
                if stage != .intro {
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
        VStack(spacing: 0) {
            Spacer(minLength: 70)
            introSymbol
            Text("onboarding.question")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 28)
            Text("onboarding.answer")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Spacer(minLength: 58)
            PrimaryActionButton(
                title: "onboarding.start",
                symbol: "arrow.right",
                tint: .blue,
                action: { move(to: .stock) }
            )
            Label("onboarding.offline", systemImage: "wifi.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
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
            subtitle: String(localized: "onboarding.stock.subtitle"),
            accent: .blue
        ) {
            LazyVStack(spacing: 10) {
                ForEach(model.securities) { security in
                    Button {
                        model.selectSecurity(security)
                    } label: {
                        SelectionRow(
                            title: security.name,
                            subtitle: securitySubtitle(security),
                            selected: model.selectedSecurityID == security.id,
                            accent: .blue
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var strategyStep: some View {
        StepContainer(
            symbol: "slider.horizontal.3",
            title: String(localized: "onboarding.strategy.title"),
            subtitle: String(localized: "onboarding.strategy.subtitle"),
            accent: .purple
        ) {
            LazyVStack(spacing: 10) {
                ForEach(model.strategies) { strategy in
                    Button {
                        model.selectStrategy(strategy)
                    } label: {
                        SelectionRow(
                            title: strategy.name,
                            subtitle: strategy.summary,
                            selected: model.selectedStrategyID == strategy.id,
                            accent: .purple
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var settingsStep: some View {
        StepContainer(
            symbol: "calendar.badge.clock",
            title: String(localized: "onboarding.settings.title"),
            subtitle: String(localized: "onboarding.settings.subtitle"),
            accent: .orange
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
            .padding(18)
            .background(.background, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            }
        }
    }

    private var runStep: some View {
        StepContainer(
            symbol: "play.fill",
            title: String(localized: "onboarding.run.title"),
            subtitle: String(localized: "onboarding.run.subtitle"),
            accent: .green
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ReadyRow(text: model.selectedSecurity?.name ?? "—")
                ReadyRow(text: model.selectedStrategy?.name ?? "—")
                ReadyRow(text: String(localized: "onboarding.run.conditions_ready"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.background, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        PrimaryActionButton(
            title: primaryActionTitle,
            symbol: stage == .run ? "play.fill" : "arrow.right",
            tint: stageTint,
            disabled: !canContinue,
            action: performPrimaryAction
        )
        .frame(maxWidth: 600)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var primaryActionTitle: LocalizedStringKey {
        switch stage {
        case .settings: "onboarding.settings.confirm"
        case .run: "onboarding.run.button"
        default: "action.continue"
        }
    }

    private var canContinue: Bool {
        switch stage {
        case .stock: model.selectedSecurity != nil
        case .strategy: model.selectedStrategy != nil
        default: true
        }
    }

    private var stageTint: Color {
        switch stage {
        case .intro, .stock: .blue
        case .strategy: .purple
        case .settings: .orange
        case .run: .green
        }
    }

    private func performPrimaryAction() {
        switch stage {
        case .intro: move(to: .stock)
        case .stock: move(to: .strategy)
        case .strategy: move(to: .settings)
        case .settings:
            model.hasConfirmedSettings = true
            move(to: .run)
        case .run:
            _ = model.runBacktest(completesOnboarding: true)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var selectedPeriod: String {
        guard let availableFirst = model.selectedCandles.first?.date,
              let availableLast = model.selectedCandles.last?.date
        else { return "—" }
        let first = model.settings.startDate ?? availableFirst
        let last = model.settings.endDate ?? availableLast
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
        if reduceMotion {
            stage = next
        } else {
            withAnimation(.snappy(duration: 0.42, extraBounce: 0.02)) { stage = next }
        }
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
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(1...4, id: \.self) { step in
                    Capsule()
                        .fill(colors[step - 1].opacity(step <= currentStep ? 1 : 0.14))
                        .frame(height: step == currentStep ? 6 : 4)
                        .animation(.easeInOut(duration: 0.25), value: currentStep)
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
        .padding(.vertical, 8)
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
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 50, height: 50)
                    .background(accent.opacity(0.12), in: .rect(cornerRadius: 15))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }
}

private struct SelectionRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? accent : Color.secondary.opacity(0.55))
                .font(.title3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(selected ? accent.opacity(0.10) : Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? accent.opacity(0.45) : .clear, lineWidth: 1)
        }
        .contentShape(.rect)
        .animation(.easeInOut(duration: 0.18), value: selected)
    }
}

private struct ReadyRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.primary, .green)
    }
}

private struct PrimaryActionButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    var disabled = false
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                actionButton
                    .buttonStyle(.glassProminent)
            } else {
                actionButton
                    .buttonStyle(.borderedProminent)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(tint)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }

    private var actionButton: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
    }
}
