import Foundation

enum Market: String, Codable, Sendable {
    case demo
    case us
    case hk
    case cn
}

enum MarketDataSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case offline
    case longbridge

    var id: String { rawValue }
}

enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case disabled
    case openAI
    case deepSeek

    var id: String { rawValue }
}

struct Security: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let symbol: String
    let name: String
    let market: Market
    let currency: String
    let isSyntheticDemo: Bool
}

struct Candle: Identifiable, Hashable, Codable, Sendable {
    var id: Date { date }
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
}

struct TradingStrategy: Identifiable, Hashable, Codable, Sendable {
    enum Rule: Hashable, Codable, Sendable {
        case buyAndHold
        case monthlyDCA
        case dualMovingAverage(short: Int, long: Int)
        case breakout(entryWindow: Int, exitWindow: Int)
    }

    let id: UUID
    let name: String
    let summary: String
    let rule: Rule
    let isBuiltIn: Bool

    static let dualMovingAverageDemo = TradingStrategy(
        id: UUID(uuidString: "72E7B1D4-2FE3-43C8-A09E-10471B8323AC")!,
        name: String(localized: "strategy.demo.name"),
        summary: String(localized: "strategy.demo.summary"),
        rule: .dualMovingAverage(short: 10, long: 30),
        isBuiltIn: true
    )

    static let buyAndHoldDemo = TradingStrategy(
        id: UUID(uuidString: "6B5518CF-3034-4E42-9C48-105D32105E90")!,
        name: String(localized: "strategy.buy_hold.name"),
        summary: String(localized: "strategy.buy_hold.summary"),
        rule: .buyAndHold,
        isBuiltIn: true
    )

    static let monthlyDCADemo = TradingStrategy(
        id: UUID(uuidString: "18FC7953-A3E7-4F29-BE40-6F7939C506B6")!,
        name: String(localized: "strategy.dca.name"),
        summary: String(localized: "strategy.dca.summary"),
        rule: .monthlyDCA,
        isBuiltIn: true
    )

    static let breakoutDemo = TradingStrategy(
        id: UUID(uuidString: "C0FC3762-D419-4976-9ED4-74ED70AC60D6")!,
        name: String(localized: "strategy.breakout.name"),
        summary: String(localized: "strategy.breakout.summary"),
        rule: .breakout(entryWindow: 20, exitWindow: 10),
        isBuiltIn: true
    )

    static var builtIn: [TradingStrategy] {
        [.monthlyDCADemo, .buyAndHoldDemo, .dualMovingAverageDemo, .breakoutDemo]
    }

    static func builtIn(locale: Locale) -> [TradingStrategy] {
        [
            TradingStrategy(
                id: monthlyDCADemo.id,
                name: String(localized: "strategy.dca.name", locale: locale),
                summary: String(localized: "strategy.dca.summary", locale: locale),
                rule: .monthlyDCA,
                isBuiltIn: true
            ),
            TradingStrategy(
                id: buyAndHoldDemo.id,
                name: String(localized: "strategy.buy_hold.name", locale: locale),
                summary: String(localized: "strategy.buy_hold.summary", locale: locale),
                rule: .buyAndHold,
                isBuiltIn: true
            ),
            TradingStrategy(
                id: dualMovingAverageDemo.id,
                name: String(localized: "strategy.demo.name", locale: locale),
                summary: String(localized: "strategy.demo.summary", locale: locale),
                rule: .dualMovingAverage(short: 10, long: 30),
                isBuiltIn: true
            ),
            TradingStrategy(
                id: breakoutDemo.id,
                name: String(localized: "strategy.breakout.name", locale: locale),
                summary: String(localized: "strategy.breakout.summary", locale: locale),
                rule: .breakout(entryWindow: 20, exitWindow: 10),
                isBuiltIn: true
            ),
        ]
    }
}

struct BacktestSettings: Hashable, Codable, Sendable {
    var startDate: Date? = nil
    var endDate: Date? = nil
    var initialCapital: Double
    var commissionRate: Double
    var slippageRate: Double

    static let demo = BacktestSettings(
        initialCapital: 100_000,
        commissionRate: 0.001,
        slippageRate: 0.0005
    )
}

enum TradeSide: String, Codable, Sendable {
    case buy
    case sell
}

struct SimulatedTrade: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let date: Date
    let side: TradeSide
    let price: Double
    let quantity: Int
    let fee: Double
    let reason: String
}

struct EquityPoint: Identifiable, Hashable, Codable, Sendable {
    var id: Date { date }
    let date: Date
    let strategyValue: Double
    let benchmarkValue: Double
}

struct BacktestResult: Hashable, Sendable {
    let security: Security
    let strategy: TradingStrategy
    let settings: BacktestSettings
    let candles: [Candle]
    let trades: [SimulatedTrade]
    let equityCurve: [EquityPoint]
    let finalValue: Double
    let cumulativeReturn: Double
    let benchmarkReturn: Double
    let maxDrawdown: Double
    let annualizedReturn: Double
    let annualizedVolatility: Double
    let sharpeRatio: Double?

    var excessReturn: Double { cumulativeReturn - benchmarkReturn }
    var netProfit: Double { finalValue - settings.initialCapital }
    var totalFees: Double { trades.reduce(0) { $0 + $1.fee } }
    var totalBuyCost: Double {
        trades
            .filter { $0.side == .buy }
            .reduce(0) { $0 + $1.price * Double($1.quantity) + $1.fee }
    }
}

struct BacktestRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let securityID: String
    let securitySymbol: String
    let securityName: String
    let currency: String
    let strategyID: UUID
    let strategyName: String
    let settings: BacktestSettings
    let finalValue: Double
    let cumulativeReturn: Double
    let benchmarkReturn: Double
    let maxDrawdown: Double
    let tradeCount: Int
    let annualizedReturn: Double?
    let annualizedVolatility: Double?
    let sharpeRatio: Double?
    let totalFees: Double?

    init(result: BacktestResult, createdAt: Date = .now) {
        id = UUID()
        self.createdAt = createdAt
        securityID = result.security.id
        securitySymbol = result.security.symbol
        securityName = result.security.name
        currency = result.security.currency
        strategyID = result.strategy.id
        strategyName = result.strategy.name
        settings = result.settings
        finalValue = result.finalValue
        cumulativeReturn = result.cumulativeReturn
        benchmarkReturn = result.benchmarkReturn
        maxDrawdown = result.maxDrawdown
        tradeCount = result.trades.count
        annualizedReturn = result.annualizedReturn
        annualizedVolatility = result.annualizedVolatility
        sharpeRatio = result.sharpeRatio
        totalFees = result.totalFees
    }

    var excessReturn: Double { cumulativeReturn - benchmarkReturn }
    var netProfit: Double { finalValue - settings.initialCapital }
}
