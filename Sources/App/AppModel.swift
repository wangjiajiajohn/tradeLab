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
    }

    let securities: [Security]
    let strategies: [TradingStrategy]
    let demoCandles: [Candle]

    @Published var selectedSecurityID: String?
    @Published var selectedStrategyID: UUID?
    @Published var settings = BacktestSettings.demo
    @Published var hasConfirmedSettings = false
    @Published var result: BacktestResult?
    @Published var errorMessage: String?
    @Published var selectedTab: MainTab = .backtest
    @Published var hasCompletedFirstBacktest: Bool
    @Published var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    init(defaults: UserDefaults = .standard) {
        let provider = DemoMarketDataProvider()
        securities = [provider.security]
        demoCandles = provider.candles()
        strategies = [.dualMovingAverageDemo]
        hasCompletedFirstBacktest = defaults.bool(forKey: Keys.completedFirstBacktest)
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
    }

    var selectedSecurity: Security? {
        securities.first { $0.id == selectedSecurityID }
    }

    var selectedStrategy: TradingStrategy? {
        strategies.first { $0.id == selectedStrategyID }
    }

    var canRunBacktest: Bool {
        selectedSecurity != nil && selectedStrategy != nil && hasConfirmedSettings
    }

    func selectDemoSecurity() {
        selectedSecurityID = securities.first?.id
    }

    func selectDemoStrategy() {
        selectedStrategyID = strategies.first?.id
    }

    @discardableResult
    func runBacktest(completesOnboarding: Bool = false) -> Bool {
        guard let security = selectedSecurity, let strategy = selectedStrategy, canRunBacktest else {
            errorMessage = String(localized: "error.incomplete_setup")
            return false
        }

        do {
            result = try BacktestEngine.run(
                security: security,
                candles: demoCandles,
                strategy: strategy,
                settings: settings
            )
            errorMessage = nil
            if completesOnboarding {
                hasCompletedFirstBacktest = true
                UserDefaults.standard.set(true, forKey: Keys.completedFirstBacktest)
            }
            selectedTab = .backtest
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func resetFirstRunExperience() {
        selectedSecurityID = nil
        selectedStrategyID = nil
        hasConfirmedSettings = false
        result = nil
        errorMessage = nil
        hasCompletedFirstBacktest = false
        UserDefaults.standard.removeObject(forKey: Keys.completedFirstBacktest)
    }
}
