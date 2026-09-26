import SwiftUI

struct StrategyListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingCreator = false

    private var builtInStrategies: [TradingStrategy] { model.strategies.filter(\.isBuiltIn) }
    private var customStrategies: [TradingStrategy] { model.strategies.filter { !$0.isBuiltIn } }

    var body: some View {
        NavigationStack {
            List {
                Section("strategies.custom") {
                    if customStrategies.isEmpty {
                        ContentUnavailableView(
                            "strategies.custom.empty_prompt",
                            systemImage: "slider.horizontal.3"
                        )
                    } else {
                        ForEach(customStrategies) { strategy in
                            strategyRow(strategy)
                                .swipeActions {
                                    Button("strategies.delete", role: .destructive) {
                                        model.deleteCustomStrategy(strategy)
                                    }
                                }
                        }
                    }
                }

                Section("strategies.built_in") {
                    ForEach(builtInStrategies) { strategy in strategyRow(strategy) }
                }
            }
            .navigationTitle(model.language.localized("tab.strategies"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("strategies.add", systemImage: "plus") { showingCreator = true }
                        .tabToolbarJellyEffect()
                }
            }
            .sheet(isPresented: $showingCreator) {
                StrategyCreatorView()
            }
        }
    }

    private func strategyRow(_ strategy: TradingStrategy) -> some View {
        NavigationLink {
            StrategyDetailView(strategy: strategy)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(strategy.name).font(.headline)
                Text(strategy.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StrategyDetailView: View {
    let strategy: TradingStrategy

    var body: some View {
        List {
            Section("strategies.rule_summary") {
                Text(strategy.summary)
            }

            Section("strategies.parameters") {
                LabeledContent("strategies.type") {
                    Text(typeName)
                }
                switch strategy.rule {
                case .dualMovingAverage(let short, let long):
                    LabeledContent("strategies.short_window", value: "\(short)")
                    LabeledContent("strategies.long_window", value: "\(long)")
                case .breakout(let entry, let exit):
                    LabeledContent("strategies.entry_window", value: "\(entry)")
                    LabeledContent("strategies.exit_window", value: "\(exit)")
                case .buyAndHold, .monthlyDCA:
                    Text("strategies.no_parameters")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Label("strategies.selection_note", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(strategy.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var typeName: LocalizedStringKey {
        switch strategy.rule {
        case .buyAndHold: "strategies.type.buy_hold"
        case .monthlyDCA: "strategies.type.dca"
        case .dualMovingAverage: "strategies.type.moving_average"
        case .breakout: "strategies.type.breakout"
        }
    }
}

private struct StrategyCreatorView: View {
    private enum CreationMode: String, CaseIterable, Identifiable {
        case describe
        case manual

        var id: String { rawValue }
    }

    private enum Kind: String, CaseIterable, Identifiable {
        case buyAndHold
        case monthlyDCA
        case movingAverage
        case breakout

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .buyAndHold: "strategies.type.buy_hold"
            case .monthlyDCA: "strategies.type.dca"
            case .movingAverage: "strategies.type.moving_average"
            case .breakout: "strategies.type.breakout"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var name = ""
    @State private var kind: Kind = .movingAverage
    @State private var creationMode: CreationMode = .describe
    @State private var strategyDescription = ""
    @State private var analysisWarnings: [String] = []
    @State private var missingFields: [String] = []
    @State private var analysisError: String?
    @State private var isAnalyzing = false
    @State private var analysisCompleted = false
    @State private var shortWindow = 10
    @State private var longWindow = 30
    @State private var entryWindow = 20
    @State private var exitWindow = 10
    @State private var showingAIConsent = false
    @AppStorage("v2.ai-consented-providers") private var consentedAIProviders = ""

    private var rule: TradingStrategy.Rule {
        switch kind {
        case .buyAndHold: .buyAndHold
        case .monthlyDCA: .monthlyDCA
        case .movingAverage: .dualMovingAverage(short: shortWindow, long: longWindow)
        case .breakout: .breakout(entryWindow: entryWindow, exitWindow: exitWindow)
        }
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if creationMode == .describe,
           (!analysisCompleted || !missingFields.isEmpty || analysisError != nil) { return false }
        return switch kind {
        case .movingAverage: shortWindow > 0 && longWindow > shortWindow
        case .breakout: entryWindow > exitWindow && exitWindow > 0
        default: true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("strategies.creation_mode", selection: $creationMode) {
                        Text("strategies.creation_mode.describe").tag(CreationMode.describe)
                        Text("strategies.creation_mode.manual").tag(CreationMode.manual)
                    }
                    .pickerStyle(.segmented)
                }
                if creationMode == .describe {
                    analysisSection
                }
                Section("strategies.name") {
                    TextField("strategies.name.placeholder", text: $name)
                }
                Section("strategies.type") {
                    Picker("strategies.type", selection: $kind) {
                        ForEach(Kind.allCases) { kind in Text(kind.title).tag(kind) }
                    }
                    .pickerStyle(.navigationLink)
                }
                parameters
                Section {
                    Label("strategies.local_note", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("strategies.create")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: strategyDescription) { _, _ in
                analysisCompleted = false
                analysisError = nil
                analysisWarnings = []
                missingFields = []
            }
            .alert("strategy_analysis.privacy_title", isPresented: $showingAIConsent) {
                Button("strategy_analysis.privacy_continue") {
                    recordAIConsent()
                    analyzeDescription()
                }
                Button("action.cancel", role: .cancel) {}
            } message: {
                Text(aiConsentMessage)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("strategies.save") {
                        model.addCustomStrategy(name: name, rule: rule)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var analysisSection: some View {
        Section("strategies.describe") {
            TextEditor(text: $strategyDescription)
                .frame(minHeight: 110)
                .overlay(alignment: .topLeading) {
                    if strategyDescription.isEmpty {
                        Text("strategies.describe.placeholder")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                requestAnalysis()
            } label: {
                HStack {
                    if isAnalyzing {
                        BacktestActivityMark(tint: .accentColor, compact: true)
                    }
                    Label("strategies.analyze", systemImage: "sparkles")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(
                isAnalyzing
                    || strategyDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.aiProvider == .disabled
                    || !model.hasAIAPIKey
            )

            if model.aiProvider == .disabled || !model.hasAIAPIKey {
                Label("strategy_analysis.not_configured", systemImage: "gearshape")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let analysisError {
                Label(analysisError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            ForEach(missingFields, id: \.self) { field in
                Label(field, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            ForEach(analysisWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var parameters: some View {
        switch kind {
        case .movingAverage:
            Section("strategies.parameters") {
                Stepper(value: $shortWindow, in: 2...100) {
                    LabeledContent("strategies.short_window", value: "\(shortWindow)")
                }
                Stepper(value: $longWindow, in: 3...250) {
                    LabeledContent("strategies.long_window", value: "\(longWindow)")
                }
                if longWindow <= shortWindow {
                    Text("strategies.error.window_order")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        case .breakout:
            Section("strategies.parameters") {
                Stepper(value: $entryWindow, in: 2...250) {
                    LabeledContent("strategies.entry_window", value: "\(entryWindow)")
                }
                Stepper(value: $exitWindow, in: 1...100) {
                    LabeledContent("strategies.exit_window", value: "\(exitWindow)")
                }
                if entryWindow <= exitWindow {
                    Text("strategies.error.breakout_order")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        case .buyAndHold, .monthlyDCA:
            Section("strategies.parameters") {
                Text("strategies.no_parameters")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aiConsentMessage: String {
        String(
            format: AppLocalization.string("strategy_analysis.privacy_message_format", locale: locale),
            model.aiProvider.displayName
        )
    }

    private var hasConsentedToCurrentAIProvider: Bool {
        Set(consentedAIProviders.split(separator: "|").map(String.init))
            .contains(model.aiProvider.rawValue)
    }

    private func requestAnalysis() {
        if hasConsentedToCurrentAIProvider {
            analyzeDescription()
        } else {
            showingAIConsent = true
        }
    }

    private func recordAIConsent() {
        var providers = Set(consentedAIProviders.split(separator: "|").map(String.init))
        providers.insert(model.aiProvider.rawValue)
        consentedAIProviders = providers.sorted().joined(separator: "|")
    }

    private func analyzeDescription() {
        isAnalyzing = true
        analysisError = nil
        analysisWarnings = []
        missingFields = []
        analysisCompleted = false
        Task {
            defer { isAnalyzing = false }
            do {
                let draft = try await StrategyAnalysisService.analyze(
                    strategyDescription,
                    provider: model.aiProvider,
                    model: model.aiModel,
                    locale: locale
                )
                apply(draft)
            } catch {
                analysisError = (error as? StrategyAnalysisError)?.localizedDescription(locale: locale)
                    ?? error.localizedDescription
            }
        }
    }

    private func apply(_ draft: StrategyDraft) {
        analysisWarnings = draft.warnings
        missingFields = draft.missingFields
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let suggestedName = draft.suggestedName {
            name = suggestedName
        }
        switch draft.kind {
        case "buy_and_hold":
            kind = .buyAndHold
        case "monthly_dca":
            kind = .monthlyDCA
        case "moving_average":
            kind = .movingAverage
            if let value = draft.shortWindow { shortWindow = value }
            if let value = draft.longWindow { longWindow = value }
        case "breakout":
            kind = .breakout
            if let value = draft.entryWindow { entryWindow = value }
            if let value = draft.exitWindow { exitWindow = value }
        default:
            analysisError = AppLocalization.string("strategy_analysis.unsupported", locale: locale)
            analysisCompleted = false
            return
        }
        analysisCompleted = true
    }
}
