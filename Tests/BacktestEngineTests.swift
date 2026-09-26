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
        XCTAssertTrue(result.annualizedReturn.isFinite)
        XCTAssertGreaterThanOrEqual(result.annualizedVolatility, 0)
        XCTAssertEqual(result.totalFees, result.trades.reduce(0) { $0 + $1.fee }, accuracy: 0.000_001)
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

    func testBacktestRecordCanBePersisted() throws {
        let provider = DemoMarketDataProvider()
        let result = try BacktestEngine.run(
            security: provider.security,
            candles: provider.candles(),
            strategy: .dualMovingAverageDemo,
            settings: .demo
        )
        let record = BacktestRecord(
            result: result,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(record)
        let restored = try JSONDecoder().decode(BacktestRecord.self, from: data)

        XCTAssertEqual(restored, record)
        XCTAssertEqual(restored.securityID, result.security.id)
        XCTAssertEqual(restored.strategyID, result.strategy.id)
        XCTAssertEqual(restored.tradeCount, result.trades.count)
        XCTAssertEqual(restored.excessReturn, result.excessReturn, accuracy: 0.000_001)
        XCTAssertEqual(restored.annualizedReturn, result.annualizedReturn)
        XCTAssertEqual(restored.annualizedVolatility, result.annualizedVolatility)
        XCTAssertEqual(restored.sharpeRatio, result.sharpeRatio)
        XCTAssertEqual(restored.totalFees, result.totalFees)
    }

    func testLegacyBacktestRecordWithoutRiskMetricsStillDecodes() throws {
        let provider = DemoMarketDataProvider()
        let result = try BacktestEngine.run(
            security: provider.security,
            candles: provider.candles(),
            strategy: .buyAndHoldDemo,
            settings: .demo
        )
        let encoded = try JSONEncoder().encode(BacktestRecord(result: result))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "annualizedReturn")
        object.removeValue(forKey: "annualizedVolatility")
        object.removeValue(forKey: "sharpeRatio")
        object.removeValue(forKey: "totalFees")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(BacktestRecord.self, from: legacyData)

        XCTAssertNil(restored.annualizedReturn)
        XCTAssertNil(restored.annualizedVolatility)
        XCTAssertNil(restored.sharpeRatio)
        XCTAssertNil(restored.totalFees)
    }

    @MainActor
    func testCustomStrategyPersistsAcrossModelInstances() throws {
        let suiteName = "TradeLabV2Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstModel = AppModel(defaults: defaults)
        firstModel.addCustomStrategy(
            name: "Test Trend",
            rule: .dualMovingAverage(short: 7, long: 21)
        )

        let saved = try XCTUnwrap(firstModel.strategies.first { !$0.isBuiltIn })
        let restoredModel = AppModel(defaults: defaults)
        let restored = try XCTUnwrap(restoredModel.strategies.first { $0.id == saved.id })

        XCTAssertEqual(restored.name, "Test Trend")
        XCTAssertEqual(restored.rule, .dualMovingAverage(short: 7, long: 21))
    }

    func testBacktestUsesOnlySelectedDateRange() throws {
        let provider = DemoMarketDataProvider()
        let candles = provider.candles()
        var settings = BacktestSettings.demo
        settings.startDate = candles[20].date
        settings.endDate = candles[80].date

        let result = try BacktestEngine.run(
            security: provider.security,
            candles: candles,
            strategy: .buyAndHoldDemo,
            settings: settings
        )

        XCTAssertEqual(result.candles.first?.date, candles[20].date)
        XCTAssertEqual(result.candles.last?.date, candles[80].date)
        XCTAssertEqual(result.trades.first?.date, candles[20].date)
        XCTAssertEqual(result.trades.last?.date, candles[80].date)
    }

    func testBacktestRejectsReversedDateRange() {
        let provider = DemoMarketDataProvider()
        let candles = provider.candles()
        var settings = BacktestSettings.demo
        settings.startDate = candles[80].date
        settings.endDate = candles[20].date

        XCTAssertThrowsError(
            try BacktestEngine.run(
                security: provider.security,
                candles: candles,
                strategy: .buyAndHoldDemo,
                settings: settings
            )
        ) { error in
            guard case BacktestError.invalidPeriod = error else {
                return XCTFail("Expected invalidPeriod, received \(error)")
            }
        }
    }
}
