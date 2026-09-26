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

    func testEveryBuiltInStrategyRunsAndClosesItsPosition() throws {
        let provider = DemoMarketDataProvider()
        for strategy in TradingStrategy.builtIn {
            let result = try BacktestEngine.run(
                security: provider.security,
                candles: provider.candles(),
                strategy: strategy,
                settings: .demo
            )
            if !result.trades.isEmpty {
                XCTAssertEqual(result.trades.first?.side, .buy, strategy.name)
                XCTAssertEqual(result.trades.last?.side, .sell, strategy.name)
            }
            XCTAssertGreaterThan(result.finalValue, 0, strategy.name)
        }
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

    func testMonthlyDCAInvestsOnEachMonthsFirstTradingDayAndCloses() throws {
        let provider = DemoMarketDataProvider()
        let result = try BacktestEngine.run(
            security: provider.security,
            candles: provider.candles(),
            strategy: .monthlyDCADemo,
            settings: .demo
        )

        let buys = result.trades.filter { $0.side == .buy }
        let calendar = Calendar(identifier: .gregorian)
        let investedMonths = Set(buys.map { calendar.dateComponents([.year, .month], from: $0.date) })
        let candles = provider.candles()

        XCTAssertEqual(buys.count, investedMonths.count)
        XCTAssertGreaterThan(buys.count, 1)
        XCTAssertEqual(result.trades.last?.side, .sell)
        XCTAssertLessThanOrEqual(result.totalBuyCost, BacktestSettings.demo.initialCapital + 0.01)

        for buy in buys {
            let month = calendar.dateComponents([.year, .month], from: buy.date)
            let firstTradingDate = candles
                .filter { calendar.dateComponents([.year, .month], from: $0.date) == month }
                .map(\.date)
                .min()
            XCTAssertEqual(buy.date, firstTradingDate)
        }
    }
}
