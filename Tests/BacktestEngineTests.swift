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

    func testBacktestDiagnosticsAlwaysExplainTheCurrentResult() throws {
        let provider = DemoMarketDataProvider()
        for strategy in TradingStrategy.builtIn {
            let result = try BacktestEngine.run(
                security: provider.security,
                candles: provider.candles(),
                strategy: strategy,
                settings: .demo
            )
            let report = BacktestDiagnostics.report(result)
            let diagnostics = report.diagnostics

            XCTAssertFalse(diagnostics.isEmpty, strategy.name)
            XCTAssertLessThanOrEqual(diagnostics.count, 4, strategy.name)
            XCTAssertEqual(Set(diagnostics.map(\.id)).count, diagnostics.count, strategy.name)
            XCTAssertGreaterThanOrEqual(report.curve.annualizedVolatility, 0, strategy.name)
            XCTAssertGreaterThanOrEqual(report.curve.maximumDrawdown, 0, strategy.name)
            XCTAssertFalse(report.optimizations.isEmpty, strategy.name)
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

    func testTradeJournalCalculatesFIFORealizedProfitAndPosition() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let trades = [
            JournalTrade(date: date, symbol: "AAPL", side: .buy, quantity: 10, price: 100, fee: 10, currency: "USD"),
            JournalTrade(date: date.addingTimeInterval(60), symbol: "AAPL", side: .buy, quantity: 10, price: 120, fee: 0, currency: "USD"),
            JournalTrade(date: date.addingTimeInterval(120), symbol: "AAPL", side: .sell, quantity: 15, price: 150, fee: 5, currency: "USD")
        ]

        let analysis = TradeJournalAnalyzer.analyze(trades)
        let usd = try! XCTUnwrap(analysis.summaries.first { $0.currency == "USD" })
        let position = try! XCTUnwrap(analysis.positions.first { $0.symbol == "AAPL" })

        XCTAssertEqual(usd.realizedProfit, 635, accuracy: 0.000_001)
        XCTAssertEqual(usd.fees, 15, accuracy: 0.000_001)
        XCTAssertEqual(position.quantity, 5, accuracy: 0.000_001)
        XCTAssertEqual(position.averageCost, 120, accuracy: 0.000_001)
        XCTAssertTrue(analysis.oversoldSymbols.isEmpty)
    }

    func testTradeJournalReportsSellWithoutRecordedHoldings() {
        let trade = JournalTrade(
            date: .now,
            symbol: "700.HK",
            side: .sell,
            quantity: 100,
            price: 400,
            currency: "HKD"
        )
        let analysis = TradeJournalAnalyzer.analyze([trade])
        XCTAssertEqual(analysis.oversoldSymbols, ["700.HK"])
        XCTAssertEqual(analysis.summaries.first?.realizedProfit, 0)
    }

    func testCSVImporterSupportsEnglishAndChineseColumns() throws {
        let english = "date,symbol,side,quantity,price,fee,currency\n2026-09-01,AAPL,buy,10,200,1,USD\n"
        let chinese = "交易日期,股票代码,方向,数量,成交价,手续费,币种\n2026/09/02,700.HK,卖出,100,410,12,HKD\n"

        let first = try TradeCSVImporter.parse(data: Data(english.utf8))
        let second = try TradeCSVImporter.parse(data: Data(chinese.utf8))

        XCTAssertEqual(first.trades.first?.symbol, "AAPL")
        XCTAssertEqual(first.trades.first?.side, .buy)
        XCTAssertEqual(second.trades.first?.symbol, "700.HK")
        XCTAssertEqual(second.trades.first?.side, .sell)
        XCTAssertEqual(second.rejectedRows, 0)
    }

    func testLongbridgeSearchNormalizationIsCompanyAgnostic() {
        XCTAssertEqual(LongbridgeMarketDataProvider.normalizedSearchText("  NIO  "), "nio")
        XCTAssertEqual(LongbridgeMarketDataProvider.normalizedSearchText("ＡＡＰＬ"), "aapl")
        XCTAssertEqual(LongbridgeMarketDataProvider.normalizedSearchText("蔚来汽车"), "蔚来汽车")
    }

    @MainActor
    func testWorkspaceRestoresAfterRelaunch() throws {
        let suiteName = "TradeLabV2Tests.workspace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = AppModel(defaults: defaults)
        let security = try XCTUnwrap(model.securities.first)
        let strategy = try XCTUnwrap(model.strategies.first)
        let settings = BacktestSettings(
            startDate: nil,
            endDate: nil,
            initialCapital: 88_000,
            commissionRate: 0.0008,
            slippageRate: 0.0003
        )
        model.selectSecurity(security)
        model.selectStrategy(strategy)
        model.updateSettings(settings)
        model.hasConfirmedSettings = true
        model.result = try BacktestEngine.run(
            security: security,
            candles: model.candles(for: security),
            strategy: strategy,
            settings: settings
        )

        let restored = AppModel(defaults: defaults)

        XCTAssertEqual(restored.selectedSecurityID, security.id)
        XCTAssertEqual(restored.selectedStrategyID, strategy.id)
        XCTAssertEqual(restored.settings, settings)
        XCTAssertTrue(restored.hasConfirmedSettings)
        XCTAssertEqual(restored.result?.security.id, security.id)
        XCTAssertEqual(restored.result?.strategy.id, strategy.id)
        XCTAssertEqual(restored.result?.finalValue, model.result?.finalValue)
    }
}
