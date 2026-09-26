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

    private enum Keys {
        static let completedFirstBacktest = "v2.completed-first-backtest"
        static let appearance = "v2.appearance"
        static let backtestHistory = "v2.backtest-history"
        static let customStrategies = "v2.custom-strategies"
        static let marketDataSource = "v2.market-data-source"
        static let aiProvider = "v2.ai-provider"
        static let aiModel = "v2.ai-model"
        static let journalTrades = "v2.journal-trades"
    }

    private let defaults: UserDefaults
    let securities: [Security]
    @Published private(set) var strategies: [TradingStrategy]
    private let marketData: MarketDataLibrary

    @Published var selectedSecurityID: String?
    @Published var selectedStrategyID: UUID?
    @Published var settings = BacktestSettings.demo
    @Published var hasConfirmedSettings = false
    @Published var result: BacktestResult?
    @Published var errorMessage: String?
    @Published var selectedTab: MainTab = .backtest
    @Published var hasCompletedFirstBacktest: Bool
    @Published private(set) var backtestHistory: [BacktestRecord]
    @Published var marketDataSource: MarketDataSource {
        didSet { defaults.set(marketDataSource.rawValue, forKey: Keys.marketDataSource) }
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
    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let library = BuiltInMarketDataProvider.load()
        marketData = library
        securities = library.securities
        strategies = TradingStrategy.builtIn + Self.loadCustomStrategies(from: defaults)
        hasCompletedFirstBacktest = defaults.bool(forKey: Keys.completedFirstBacktest)
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        backtestHistory = Self.loadHistory(from: defaults)
        marketDataSource = MarketDataSource(rawValue: defaults.string(forKey: Keys.marketDataSource) ?? "") ?? .offline
        aiProvider = AIProvider(rawValue: defaults.string(forKey: Keys.aiProvider) ?? "") ?? .disabled
        aiModel = defaults.string(forKey: Keys.aiModel) ?? "deepseek-chat"
        journalTrades = Self.loadJournalTrades(from: defaults)
        refreshCredentialStatus()
    }

    var selectedSecurity: Security? {
        securities.first { $0.id == selectedSecurityID }
    }

    var selectedStrategy: TradingStrategy? {
        strategies.first { $0.id == selectedStrategyID }
    }

    var selectedCandles: [Candle] {
        guard let selectedSecurity else { return [] }
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
    func runBacktest(completesOnboarding: Bool = false) -> Bool {
        guard let security = selectedSecurity, let strategy = selectedStrategy, canRunBacktest else {
            errorMessage = String(localized: "error.incomplete_setup")
            return false
        }

        do {
            let newResult = try BacktestEngine.run(
                security: security,
                candles: candles(for: security),
                strategy: strategy,
                settings: settings
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
            errorMessage = error.localizedDescription
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
            String(localized: "strategy.buy_hold.summary")
        case .monthlyDCA:
            String(localized: "strategy.dca.summary")
        case let .dualMovingAverage(short, long):
            String(
                format: String(localized: "strategies.summary.moving_average_format"),
                short,
                long,
                short,
                long
            )
        case let .breakout(entryWindow, exitWindow):
            String(
                format: String(localized: "strategies.summary.breakout_format"),
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
