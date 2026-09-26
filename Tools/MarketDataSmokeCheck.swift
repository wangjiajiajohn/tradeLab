import Foundation

@main
enum MarketDataSmokeCheck {
    static func main() throws {
        let library = BuiltInMarketDataProvider.load()
        precondition(library.securities.count == 7)

        var runs = 0
        for security in library.securities {
            let candles = library.candles(for: security.id)
            precondition(candles.count >= 240, security.id)
            precondition(zip(candles, candles.dropFirst()).allSatisfy { $0.date < $1.date })

            for strategy in TradingStrategy.builtIn {
                let result = try BacktestEngine.run(
                    security: security,
                    candles: candles,
                    strategy: strategy,
                    settings: .demo
                )
                precondition(result.finalValue > 0)
                precondition(result.equityCurve.count == candles.count)
                if !result.trades.isEmpty {
                    precondition(result.trades.first?.side == .buy)
                    precondition(result.trades.last?.side == .sell)
                }
                runs += 1
            }
        }

        print("PASS securities=\(library.securities.count) strategies=\(TradingStrategy.builtIn.count) runs=\(runs)")
    }
}
