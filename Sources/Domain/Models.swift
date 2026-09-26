import Foundation

enum Market: String, Codable, Sendable {
    case demo
    case us
    case hk
    case cn
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
        case dualMovingAverage(short: Int, long: Int)
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
}

struct BacktestSettings: Hashable, Codable, Sendable {
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

    var excessReturn: Double { cumulativeReturn - benchmarkReturn }
}

