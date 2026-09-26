import Foundation

@main
enum EngineSmokeCheck {
    static func main() throws {
        let provider = DemoMarketDataProvider()
        let candles = provider.candles()
        let first = try BacktestEngine.run(
            security: provider.security,
            candles: candles,
            strategy: .dualMovingAverageDemo,
            settings: .demo
        )
        let second = try BacktestEngine.run(
            security: provider.security,
            candles: candles,
            strategy: .dualMovingAverageDemo,
            settings: .demo
        )

        precondition(candles.count == 520)
        precondition(!first.trades.isEmpty)
        precondition(first.trades.first?.side == .buy)
        precondition(first.trades.last?.side == .sell)
        precondition(first.finalValue > 0)
        precondition(first.maxDrawdown >= 0)
        precondition(abs(first.finalValue - second.finalValue) < 0.0001)
        precondition(abs(first.cumulativeReturn - second.cumulativeReturn) < 0.000_001)

        do {
            _ = try BacktestEngine.run(
                security: provider.security,
                candles: Array(candles.prefix(10)),
                strategy: .dualMovingAverageDemo,
                settings: .demo
            )
            preconditionFailure("Insufficient data should be rejected")
        } catch BacktestError.insufficientData {
            // Expected.
        }

        print(
            "PASS candles=\(candles.count) trades=\(first.trades.count) " +
            "final=\(String(format: "%.2f", first.finalValue)) " +
            "return=\(String(format: "%.4f", first.cumulativeReturn))"
        )
    }
}
