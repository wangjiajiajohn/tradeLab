import Foundation

protocol MarketDataProviding: Sendable {
    var security: Security { get }
    func candles() -> [Candle]
}

struct DemoMarketDataProvider: MarketDataProviding {
    let security = Security(
        id: "AAPL-DEMO.US",
        symbol: "AAPL",
        name: "Apple",
        market: .demo,
        currency: "USD",
        isSyntheticDemo: true
    )

    func candles() -> [Candle] {
        Self.candles(seed: 1)
    }

    static func candles(seed: Int) -> [Candle] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 2))!
        var output: [Candle] = []
        var date = start
        var tradingDay = 0

        while output.count < 520 {
            let weekday = calendar.component(.weekday, from: date)
            if weekday != 1 && weekday != 7 {
                let index = Double(tradingDay)
                let seedValue = Double(seed)
                let trend = 68 + seedValue * 22 + index * (0.06 + seedValue * 0.008)
                let mediumCycle = sin(index / (15 + seedValue) + seedValue) * (5 + seedValue)
                let longCycle = sin(index / (48 + seedValue * 3)) * (9 + seedValue)
                let shock = index > 260 && index < 330 ? -12 * sin((index - 260) / 70 * .pi) : 0
                let close = max(30, trend + mediumCycle + longCycle + shock)
                let open = close * (1 + sin(index * 1.7) * 0.004)
                let high = max(open, close) * (1.008 + abs(sin(index / 7)) * 0.006)
                let low = min(open, close) * (0.992 - abs(cos(index / 9)) * 0.005)
                let volume = 42_000_000 + (sin(index / 11) + 1) * 9_000_000
                output.append(Candle(date: date, open: open, high: high, low: low, close: close, volume: volume))
                tradingDay += 1
            }
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }

        return output
    }
}
