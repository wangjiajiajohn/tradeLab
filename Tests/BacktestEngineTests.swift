import XCTest
@testable import TradeLabV2

final class BacktestEngineTests: XCTestCase {
    func testDemoBacktestIsDeterministic() throws {
        let provider = DemoMarketDataProvider()
        let first = try BacktestEngine.run(
            security: provider.security,
            candles: provider.candles(),
            strategy: .dualMovingAverageDemo,
            settings: .demo
        )
        let second = try BacktestEngine.run(
            security: provider.security,
            candles: provider.candles(),
            strategy: .dualMovingAverageDemo,
            settings: .demo
        )

        XCTAssertEqual(first.finalValue, second.finalValue, accuracy: 0.0001)
        XCTAssertEqual(first.cumulativeReturn, second.cumulativeReturn, accuracy: 0.000_001)
        XCTAssertEqual(first.maxDrawdown, second.maxDrawdown, accuracy: 0.000_001)
        XCTAssertEqual(first.trades.count, second.trades.count)
    }

    func testDemoBacktestProducesClosedTrades() throws {
        let provider = DemoMarketDataProvider()
        let result = try BacktestEngine.run(
            security: provider.security,
            candles: provider.candles(),
            strategy: .dualMovingAverageDemo,
            settings: .demo
        )

        XCTAssertFalse(result.trades.isEmpty)
        XCTAssertEqual(result.trades.first?.side, .buy)
        XCTAssertEqual(result.trades.last?.side, .sell)
        XCTAssertGreaterThan(result.finalValue, 0)
        XCTAssertGreaterThanOrEqual(result.maxDrawdown, 0)
    }

    func testRejectsInsufficientData() {
        let provider = DemoMarketDataProvider()
        XCTAssertThrowsError(
            try BacktestEngine.run(
                security: provider.security,
                candles: Array(provider.candles().prefix(10)),
                strategy: .dualMovingAverageDemo,
                settings: .demo
            )
        )
    }
}

