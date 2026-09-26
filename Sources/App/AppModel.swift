import Foundation
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
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
            String(localized: String.LocalizationValue(key), locale: locale)
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
    }

    private let defaults: UserDefaults
    @Published private(set) var securities: [Security]
    @Published private(set) var strategies: [TradingStrategy]
    private var marketData: MarketDataLibrary

    @Published var selectedSecurityID: String?
    @Published var selectedStrategyID: UUID?
    @Published var settings = BacktestSettings.demo
    @Published var hasConfirmedSettings = false
    @Published var result: BacktestResult?
    @Published var errorMessage: String?
    @Published private(set) var isRunningBacktest = false
    @Published var selectedTab: MainTab = .backtest
    @Published var hasCompletedFirstBacktest: Bool
    @Published private(set) var backtestHistory: [BacktestRecord]
    @Published var marketDataSource: MarketDataSource {
        didSet {
            defaults.set(marketDataSource.rawValue, forKey: Keys.marketDataSource)
            result = nil
        }
    }
    @Published var aiProvider: AIProvider {
        didSet { defaults.set(aiProvider.rawValue, forKey: Keys.aiProvider) }
    }
    @Published var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Keys.aiModel) }
    }
    @Published private(set) var hasLongbridgeCredentials = false
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
        strategies = TradingStrategy.builtIn(locale: initialLanguage.locale)
            + Self.loadCustomStrategies(from: defaults)
        hasCompletedFirstBacktest = defaults.bool(forKey: Keys.completedFirstBacktest)
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        backtestHistory = Self.loadHistory(from: defaults)
        marketDataSource = MarketDataSource(rawValue: defaults.string(forKey: Keys.marketDataSource) ?? "") ?? .offline
        aiProvider = AIProvider(rawValue: defaults.string(forKey: Keys.aiProvider) ?? "") ?? .disabled
        aiModel = defaults.string(forKey: Keys.aiModel) ?? "deepseek-chat"
        journalTrades = Self.loadJournalTrades(from: defaults)
        refreshCredentialStatus()
    }

    private func reloadLocalizedContent() {
        let customStrategies = strategies.filter { !$0.isBuiltIn }
        let library = BuiltInMarketDataProvider.load(locale: language.locale)
        marketData = library
        securities = library.securities
        strategies = TradingStrategy.builtIn(locale: language.locale) + customStrategies
    }

    var selectedSecurity: Security? {
        securities.first { $0.id == selectedSecurityID }
    }

    var selectedStrategy: TradingStrategy? {
        strategies.first { $0.id == selectedStrategyID }
    }

    var selectedCandles: [Candle] {
        guard let selectedSecurity else { return [] }
        if marketDataSource == .longbridge,
           let cached = onlineCandles[selectedSecurity.id] { return cached }
        return candles(for: selectedSecurity)
    }

    var canRunBacktest: Bool {
        selectedSecurity != nil && selectedStrategy != nil && hasConfirmedSettings
    }

    func selectSecurity(_ security: Security) {
        guard selectedSecurityID != security.id else { return }
        selectedSecurityID = security.id
        result = nil
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
        defer { isRunningBacktest = false }
        do {
            let inputCandles: [Candle]
            if marketDataSource == .longbridge {
                guard let credentials = LongbridgeCredentials.saved else {
                    throw OnlineMarketDataError.missingCredentials
                }
                let end = settings.endDate ?? Date()
                let start = settings.startDate
                    ?? Calendar(identifier: .gregorian).date(byAdding: .year, value: -2, to: end)
                    ?? end.addingTimeInterval(-730 * 86_400)
                inputCandles = try await LongbridgeMarketDataProvider(credentials: credentials)
                    .dailyCandles(for: security, from: start, to: end)
                onlineCandles[security.id] = inputCandles
            } else {
                inputCandles = candles(for: security)
            }
            let resultSecurity = marketDataSource == .longbridge
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
        securities.contains(where: { $0.id == record.securityID })
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
        hasAIAPIKey = CredentialStore.hasValue(for: .aiAPIKey)
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
