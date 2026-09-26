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
    }

    private let defaults: UserDefaults
    let securities: [Security]
    let strategies: [TradingStrategy]
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
    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let library = BuiltInMarketDataProvider.load()
        marketData = library
        securities = library.securities
        strategies = TradingStrategy.builtIn
        hasCompletedFirstBacktest = defaults.bool(forKey: Keys.completedFirstBacktest)
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        backtestHistory = Self.loadHistory(from: defaults)
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
        guard securities.contains(where: { $0.id == record.securityID }),
              strategies.contains(where: { $0.id == record.strategyID })
        else { return }
        selectedSecurityID = record.securityID
        selectedStrategyID = record.strategyID
        settings = record.settings
        hasConfirmedSettings = true
        result = nil
        selectedTab = .backtest
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
}
