import Foundation
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum BacktestRunPhase {
        case idle
        case loadingData
        case executingStrategy
        case generatingReport

        var localizationKey: String {
            switch self {
            case .idle: "backtest.running"
            case .loadingData: "backtest.running.loading_data"
            case .executingStrategy: "backtest.running.executing_strategy"
            case .generatingReport: "backtest.running.generating_report"
            }
        }
    }

    enum MainTab: Hashable {
        case backtest
        case strategies
        case review
        case settings
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum AppLanguage: String, CaseIterable, Identifiable {
        case english = "en"
        case simplifiedChinese = "zh-Hans"
        case traditionalChinese = "zh-Hant"

        var id: String { rawValue }
        var locale: Locale { Locale(identifier: rawValue) }

        var displayName: String {
            switch self {
            case .english: "English"
            case .simplifiedChinese: "简体中文"
            case .traditionalChinese: "繁體中文"
            }
        }

        func localized(_ key: String) -> String {
            AppLocalization.string(key, locale: locale)
        }
    }

    private enum Keys {
        static let completedFirstBacktest = "v2.completed-first-backtest"
        static let appearance = "v2.appearance"
        static let language = "v2.language"
        static let backtestHistory = "v2.backtest-history"
        static let customStrategies = "v2.custom-strategies"
        static let marketDataSource = "v2.market-data-source"
        static let aiProvider = "v2.ai-provider"
        static let aiModel = "v2.ai-model"
        static let journalTrades = "v2.journal-trades"
        static let selectedSecurityID = "v2.workspace.selected-security-id"
        static let selectedStrategyID = "v2.workspace.selected-strategy-id"
        static let backtestSettings = "v2.workspace.backtest-settings"
        static let confirmedSettings = "v2.workspace.confirmed-settings"
        static let latestResult = "v2.workspace.latest-result"
        static let discoveredSecurities = "v2.discovered-securities"
    }

    private let defaults: UserDefaults
    @Published private(set) var securities: [Security]
    @Published private(set) var discoveredSecurities: [Security]
    @Published private(set) var strategies: [TradingStrategy]
    private var marketData: MarketDataLibrary

    @Published var selectedSecurityID: String? {
        didSet { persistOptional(selectedSecurityID, forKey: Keys.selectedSecurityID) }
    }
    @Published var selectedStrategyID: UUID? {
        didSet { persistOptional(selectedStrategyID?.uuidString, forKey: Keys.selectedStrategyID) }
    }
    @Published var settings = BacktestSettings.demo {
        didSet { persist(settings, forKey: Keys.backtestSettings) }
    }
    @Published var hasConfirmedSettings = false {
        didSet { defaults.set(hasConfirmedSettings, forKey: Keys.confirmedSettings) }
    }
    @Published var result: BacktestResult? {
        didSet {
            if let result {
                persist(result, forKey: Keys.latestResult)
            } else {
                defaults.removeObject(forKey: Keys.latestResult)
            }
        }
    }
    @Published var errorMessage: String?
    @Published private(set) var isRunningBacktest = false
    @Published private(set) var backtestRunPhase: BacktestRunPhase = .idle
    @Published var selectedTab: MainTab = .backtest
    @Published var hasCompletedFirstBacktest: Bool
    @Published private(set) var backtestHistory: [BacktestRecord]
    @Published var marketDataSource: MarketDataSource {
        didSet {
            defaults.set(marketDataSource.rawValue, forKey: Keys.marketDataSource)
            onlineCandles.removeAll()
            result = nil
        }
    }
    @Published var aiProvider: AIProvider {
        didSet {
            defaults.set(aiProvider.rawValue, forKey: Keys.aiProvider)
            refreshCredentialStatus()
        }
    }
    @Published var aiModel: String {
        didSet {
            defaults.set(aiModel, forKey: Keys.aiModel)
            defaults.set(aiModel, forKey: aiModelKey(for: aiProvider))
        }
    }
    @Published private(set) var hasLongbridgeCredentials = false
    @Published private(set) var hasAlpacaCredentials = false
    @Published private(set) var hasTwelveDataCredentials = false
    @Published private(set) var hasAIAPIKey = false
    @Published private(set) var journalTrades: [JournalTrade]
    private var onlineCandles: [String: [Candle]] = [:]
    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            reloadLocalizedContent()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initialLanguage = AppLanguage(
            rawValue: defaults.string(forKey: Keys.language) ?? ""
        ) ?? .english
        language = initialLanguage
        let library = BuiltInMarketDataProvider.load(locale: initialLanguage.locale)
        marketData = library
        securities = library.securities
        discoveredSecurities = Self.loadDiscoveredSecurities(from: defaults)
        strategies = TradingStrategy.builtIn(locale: initialLanguage.locale)
            + Self.loadCustomStrategies(from: defaults)
        selectedSecurityID = nil
        selectedStrategyID = nil
        settings = .demo
        hasConfirmedSettings = false
        result = nil
        hasCompletedFirstBacktest = defaults.bool(forKey: Keys.completedFirstBacktest)
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        backtestHistory = Self.loadHistory(from: defaults)
        marketDataSource = MarketDataSource(rawValue: defaults.string(forKey: Keys.marketDataSource) ?? "") ?? .offline
        let initialAIProvider = AIProvider(rawValue: defaults.string(forKey: Keys.aiProvider) ?? "") ?? .disabled
        aiProvider = initialAIProvider
        aiModel = defaults.string(forKey: Self.aiModelKey(for: initialAIProvider))
            ?? defaults.string(forKey: Keys.aiModel)
            ?? ""
        journalTrades = Self.loadJournalTrades(from: defaults)
        migrateLegacyAIKey(to: initialAIProvider)
        refreshCredentialStatus()

        let storedSecurityID = defaults.string(forKey: Keys.selectedSecurityID)
        selectedSecurityID = (securities + discoveredSecurities).contains { $0.id == storedSecurityID }
            ? storedSecurityID
            : nil
        let storedStrategyID = defaults.string(forKey: Keys.selectedStrategyID).flatMap(UUID.init(uuidString:))
        selectedStrategyID = strategies.contains { $0.id == storedStrategyID }
            ? storedStrategyID
            : nil
        settings = Self.load(BacktestSettings.self, from: defaults, key: Keys.backtestSettings) ?? .demo
        let hasValidWorkspace = selectedSecurityID != nil && selectedStrategyID != nil
        hasConfirmedSettings = hasValidWorkspace && defaults.bool(forKey: Keys.confirmedSettings)
        if let storedResult = Self.load(BacktestResult.self, from: defaults, key: Keys.latestResult),
           storedResult.security.id == selectedSecurityID,
           storedResult.strategy.id == selectedStrategyID,
           hasValidWorkspace {
            result = storedResult
        }
    }

    private func reloadLocalizedContent() {
        let customStrategies = strategies.filter { !$0.isBuiltIn }
        let library = BuiltInMarketDataProvider.load(locale: language.locale)
        marketData = library
        securities = library.securities
        strategies = TradingStrategy.builtIn(locale: language.locale) + customStrategies
    }

    var selectedSecurity: Security? {
        (securities + discoveredSecurities).first { $0.id == selectedSecurityID }
    }

    var selectedStrategy: TradingStrategy? {
        strategies.first { $0.id == selectedStrategyID }
    }

    func localizedSecurityName(id: String, fallback: String) -> String {
        (securities + discoveredSecurities).first { $0.id == id }?.name ?? fallback
    }

    func localizedStrategyName(id: UUID, fallback: String) -> String {
        strategies.first { $0.id == id }?.name ?? fallback
    }

    var selectedCandles: [Candle] {
        guard let selectedSecurity else { return [] }
        if marketDataSource != .offline {
            return onlineCandles[selectedSecurity.id] ?? []
        }
        return candles(for: selectedSecurity)
    }

    var hasSelectedMarketDataCredentials: Bool {
        switch marketDataSource {
        case .offline: true
        case .longbridge: hasLongbridgeCredentials
        case .alpaca: hasAlpacaCredentials
        case .twelveData: hasTwelveDataCredentials
        }
    }

    var canRunBacktest: Bool {
        selectedSecurity != nil && selectedStrategy != nil && hasConfirmedSettings
    }

    func selectSecurity(_ security: Security) {
        if !securities.contains(where: { $0.id == security.id }) {
            discoveredSecurities.removeAll { $0.id == security.id }
            discoveredSecurities.append(security)
            saveDiscoveredSecurities()
        }
        guard selectedSecurityID != security.id else { return }
        selectedSecurityID = security.id
        result = nil
    }

    func searchSecurities(matching query: String) async throws -> [Security] {
        let cached = discoveredSecurities.filter {
            $0.name.localizedStandardContains(query)
                || $0.symbol.localizedStandardContains(query)
                || $0.id.localizedStandardContains(query)
        }
        guard marketDataSource == .longbridge else { return cached }
        guard let credentials = LongbridgeCredentials.saved else {
            throw OnlineMarketDataError.missingCredentials
        }
        let remote = try await LongbridgeMarketDataProvider(credentials: credentials)
            .searchSecurities(matching: query, locale: language.locale)
        // Keep the provider's instrument-type ranking. Locally saved matches
        // are only appended when the provider did not return that security.
        return (remote + cached).reduce(into: []) { result, security in
            if !result.contains(where: { $0.id == security.id }) { result.append(security) }
        }
    }

    func selectStrategy(_ strategy: TradingStrategy) {
        guard selectedStrategyID != strategy.id else { return }
        selectedStrategyID = strategy.id
        result = nil
    }

    func updateSettings(_ newSettings: BacktestSettings) {
        guard settings != newSettings else { return }
        settings = newSettings
        hasConfirmedSettings = false
        result = nil
    }

    func candles(for security: Security) -> [Candle] {
        marketData.candles(for: security.id)
    }

    @discardableResult
    func runBacktest(completesOnboarding: Bool = false) async -> Bool {
        guard let security = selectedSecurity, let strategy = selectedStrategy, canRunBacktest else {
            errorMessage = language.localized("error.incomplete_setup")
            return false
        }

        isRunningBacktest = true
        backtestRunPhase = .loadingData
        defer {
            backtestRunPhase = .idle
            isRunningBacktest = false
        }
        do {
            let inputCandles: [Candle]
            if marketDataSource == .offline {
                inputCandles = candles(for: security)
            } else {
                let end = settings.endDate ?? Date()
                let start = settings.startDate
                    ?? BacktestSettings.defaultPeriod(ending: end).lowerBound
                switch marketDataSource {
                case .offline:
                    inputCandles = candles(for: security)
                case .longbridge:
                guard let credentials = LongbridgeCredentials.saved else {
                    throw OnlineMarketDataError.missingCredentials
                }
                inputCandles = try await LongbridgeMarketDataProvider(credentials: credentials)
                    .dailyCandles(for: security, from: start, to: end)
                case .alpaca:
                    guard let credentials = AlpacaCredentials.saved else {
                        throw OnlineMarketDataError.missingCredentials
                    }
                    inputCandles = try await AlpacaMarketDataProvider(credentials: credentials)
                        .dailyCandles(for: security, from: start, to: end)
                case .twelveData:
                    guard let apiKey = TwelveDataMarketDataProvider.savedAPIKey else {
                        throw OnlineMarketDataError.missingCredentials
                    }
                    inputCandles = try await TwelveDataMarketDataProvider(apiKey: apiKey)
                        .dailyCandles(for: security, from: start, to: end)
                }
                onlineCandles[security.id] = inputCandles
            }
            if marketDataSource == .offline {
                try? await Task.sleep(for: .milliseconds(160))
            }
            backtestRunPhase = .executingStrategy
            if marketDataSource == .offline {
                try? await Task.sleep(for: .milliseconds(180))
            } else {
                await Task.yield()
            }
            let resultSecurity = marketDataSource != .offline
                ? Security(
                    id: security.id,
                    symbol: security.symbol,
                    name: security.name,
                    market: security.market,
                    currency: security.currency,
                    isSyntheticDemo: false
                )
                : security
            let newResult = try BacktestEngine.run(
                security: resultSecurity,
                candles: inputCandles,
                strategy: strategy,
                settings: settings,
                locale: language.locale
            )
            backtestRunPhase = .generatingReport
            if marketDataSource == .offline {
                try? await Task.sleep(for: .milliseconds(260))
            } else {
                await Task.yield()
            }
            result = newResult
            saveToHistory(newResult)
            errorMessage = nil
            if completesOnboarding {
                hasCompletedFirstBacktest = true
                defaults.set(true, forKey: Keys.completedFirstBacktest)
            }
            selectedTab = .backtest
            return true
        } catch {
            if let error = error as? BacktestError {
                errorMessage = error.localizedDescription(locale: language.locale)
            } else if let error = error as? OnlineMarketDataError {
                errorMessage = error.localizedDescription(locale: language.locale)
            } else {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func restoreConfiguration(from record: BacktestRecord) {
        guard canRestoreConfiguration(from: record) else { return }
        selectedSecurityID = record.securityID
        selectedStrategyID = record.strategyID
        settings = record.settings
        hasConfirmedSettings = true
        result = nil
        selectedTab = .backtest
    }

    func deleteBacktests(at offsets: IndexSet) {
        backtestHistory.remove(atOffsets: offsets)
        saveHistory()
    }

    func canRestoreConfiguration(from record: BacktestRecord) -> Bool {
        (securities + discoveredSecurities).contains(where: { $0.id == record.securityID })
            && strategies.contains(where: { $0.id == record.strategyID })
    }

    func addCustomStrategy(name: String, rule: TradingStrategy.Rule) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let strategy = TradingStrategy(
            id: UUID(),
            name: trimmedName,
            summary: strategySummary(for: rule),
            rule: rule,
            isBuiltIn: false
        )
        strategies.append(strategy)
        selectStrategy(strategy)
        saveCustomStrategies()
    }

    func deleteCustomStrategy(_ strategy: TradingStrategy) {
        guard !strategy.isBuiltIn else { return }
        strategies.removeAll { $0.id == strategy.id }
        if selectedStrategyID == strategy.id {
            selectedStrategyID = nil
            result = nil
        }
        saveCustomStrategies()
    }

    func resetFirstRunExperience() {
        selectedSecurityID = nil
        selectedStrategyID = nil
        hasConfirmedSettings = false
        result = nil
        errorMessage = nil
        onlineCandles.removeAll()
        hasCompletedFirstBacktest = false
        defaults.removeObject(forKey: Keys.completedFirstBacktest)
    }

    func refreshCredentialStatus() {
        hasLongbridgeCredentials = CredentialStore.hasValue(for: .longbridgeAppKey)
            && CredentialStore.hasValue(for: .longbridgeAppSecret)
            && CredentialStore.hasValue(for: .longbridgeAccessToken)
        hasAlpacaCredentials = CredentialStore.hasValue(for: .alpacaAPIKey)
            && CredentialStore.hasValue(for: .alpacaAPISecret)
        hasTwelveDataCredentials = CredentialStore.hasValue(for: .twelveDataAPIKey)
        hasAIAPIKey = aiProvider.credentialKey.map { CredentialStore.hasValue(for: $0) } ?? false
    }

    func savedAIModel(for provider: AIProvider) -> String {
        defaults.string(forKey: Self.aiModelKey(for: provider)) ?? ""
    }

    private static func aiModelKey(for provider: AIProvider) -> String {
        "\(Keys.aiModel).\(provider.rawValue)"
    }

    private func aiModelKey(for provider: AIProvider) -> String {
        Self.aiModelKey(for: provider)
    }

    private func migrateLegacyAIKey(to provider: AIProvider) {
        guard let destination = provider.credentialKey,
              !CredentialStore.hasValue(for: destination),
              let legacyValue = CredentialStore.value(for: .aiAPIKey)
        else { return }
        try? CredentialStore.set(legacyValue, for: destination)
        try? CredentialStore.remove(.aiAPIKey)
    }

    func addJournalTrade(_ trade: JournalTrade) {
        journalTrades.append(trade)
        journalTrades.sort { $0.date > $1.date }
        saveJournalTrades()
    }

    func addJournalTrades(_ trades: [JournalTrade]) {
        journalTrades.append(contentsOf: trades)
        journalTrades.sort { $0.date > $1.date }
        saveJournalTrades()
    }

    func deleteJournalTrades(at offsets: IndexSet) {
        journalTrades.remove(atOffsets: offsets)
        saveJournalTrades()
    }

    var journalAnalysis: TradeJournalAnalysis {
        TradeJournalAnalyzer.analyze(journalTrades)
    }

    private func saveToHistory(_ result: BacktestResult) {
        backtestHistory.insert(BacktestRecord(result: result), at: 0)
        backtestHistory = Array(backtestHistory.prefix(50))
        saveHistory()
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(backtestHistory) else { return }
        defaults.set(data, forKey: Keys.backtestHistory)
    }

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func persistOptional(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        from defaults: UserDefaults,
        key: String
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func loadHistory(from defaults: UserDefaults) -> [BacktestRecord] {
        guard let data = defaults.data(forKey: Keys.backtestHistory),
              let history = try? JSONDecoder().decode([BacktestRecord].self, from: data)
        else { return [] }
        return history.sorted { $0.createdAt > $1.createdAt }
    }

    private func saveJournalTrades() {
        guard let data = try? JSONEncoder().encode(journalTrades) else { return }
        defaults.set(data, forKey: Keys.journalTrades)
    }

    private func saveDiscoveredSecurities() {
        guard let data = try? JSONEncoder().encode(discoveredSecurities) else { return }
        defaults.set(data, forKey: Keys.discoveredSecurities)
    }

    private static func loadDiscoveredSecurities(from defaults: UserDefaults) -> [Security] {
        guard let data = defaults.data(forKey: Keys.discoveredSecurities),
              let securities = try? JSONDecoder().decode([Security].self, from: data)
        else { return [] }
        return securities
    }

    private static func loadJournalTrades(from defaults: UserDefaults) -> [JournalTrade] {
        guard let data = defaults.data(forKey: Keys.journalTrades),
              let trades = try? JSONDecoder().decode([JournalTrade].self, from: data)
        else { return [] }
        return trades.sorted { $0.date > $1.date }
    }

    private func strategySummary(for rule: TradingStrategy.Rule) -> String {
        switch rule {
        case .buyAndHold:
            language.localized("strategy.buy_hold.summary")
        case .monthlyDCA:
            language.localized("strategy.dca.summary")
        case let .dualMovingAverage(short, long):
            String(
                format: language.localized("strategies.summary.moving_average_format"),
                short,
                long,
                short,
                long
            )
        case let .breakout(entryWindow, exitWindow):
            String(
                format: language.localized("strategies.summary.breakout_format"),
                entryWindow,
                exitWindow
            )
        }
    }

    private func saveCustomStrategies() {
        let custom = strategies.filter { !$0.isBuiltIn }
        guard let data = try? JSONEncoder().encode(custom) else { return }
        defaults.set(data, forKey: Keys.customStrategies)
    }

    private static func loadCustomStrategies(from defaults: UserDefaults) -> [TradingStrategy] {
        guard let data = defaults.data(forKey: Keys.customStrategies),
              let strategies = try? JSONDecoder().decode([TradingStrategy].self, from: data)
        else { return [] }
        return strategies.filter { !$0.isBuiltIn }
    }
}
