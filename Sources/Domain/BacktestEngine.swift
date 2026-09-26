import Foundation

enum BacktestError: LocalizedError {
    case insufficientData
    case invalidStrategy
    case invalidCapital
    case invalidPeriod

    var errorDescription: String? {
        switch self {
        case .insufficientData: String(localized: "error.insufficient_data")
        case .invalidStrategy: String(localized: "error.invalid_strategy")
        case .invalidCapital: String(localized: "error.invalid_capital")
        case .invalidPeriod: String(localized: "error.invalid_period")
        }
    }
}

enum BacktestEngine {
    static func run(
        security: Security,
        candles: [Candle],
        strategy: TradingStrategy,
        settings: BacktestSettings
    ) throws -> BacktestResult {
        guard settings.initialCapital > 0 else { throw BacktestError.invalidCapital }
        let calendar = Calendar(identifier: .gregorian)
        if let startDate = settings.startDate, let endDate = settings.endDate,
           calendar.startOfDay(for: startDate) > calendar.startOfDay(for: endDate) {
            throw BacktestError.invalidPeriod
        }
        let candles = candles
            .filter { candle in
                let day = calendar.startOfDay(for: candle.date)
                if let startDate = settings.startDate,
                   day < calendar.startOfDay(for: startDate) { return false }
                if let endDate = settings.endDate,
                   day > calendar.startOfDay(for: endDate) { return false }
                return true
            }
            .sorted { $0.date < $1.date }

        let minimumCount: Int
        switch strategy.rule {
        case .buyAndHold, .monthlyDCA:
            minimumCount = 2
        case let .dualMovingAverage(short, long):
            guard short > 0, long > short else { throw BacktestError.invalidStrategy }
            minimumCount = long + 2
        case let .breakout(entryWindow, exitWindow):
            guard entryWindow > 1, exitWindow > 0, entryWindow > exitWindow else {
                throw BacktestError.invalidStrategy
            }
            minimumCount = entryWindow + 2
        }

        guard candles.count >= minimumCount else { throw BacktestError.insufficientData }

        var cash = settings.initialCapital
        var quantity = 0
        var trades: [SimulatedTrade] = []
        var equityCurve: [EquityPoint] = []
        var previousShort: Double?
        var previousLong: Double?
        let firstClose = candles[0].close
        let dcaMonthCount = Set(candles.map { monthKey(for: $0.date, calendar: calendar) }).count
        let monthlyInvestment = settings.initialCapital / Double(max(dcaMonthCount, 1))
        var previousDCAMonth: DateComponents?

        for index in candles.indices {
            let candle = candles[index]

            switch strategy.rule {
            case .buyAndHold:
                if index == candles.startIndex {
                    buyAll(
                        candle: candle,
                        settings: settings,
                        reason: String(localized: "trade.reason.period_start"),
                        cash: &cash,
                        quantity: &quantity,
                        trades: &trades
                    )
                }

            case .monthlyDCA:
                let month = monthKey(for: candle.date, calendar: calendar)
                if month != previousDCAMonth {
                    buy(
                        amount: monthlyInvestment,
                        candle: candle,
                        settings: settings,
                        reason: String(localized: "trade.reason.monthly_dca"),
                        cash: &cash,
                        quantity: &quantity,
                        trades: &trades
                    )
                    previousDCAMonth = month
                }

            case let .dualMovingAverage(shortWindow, longWindow):
                if index >= longWindow - 1 {
                    let shortAverage = meanClose(in: candles, endingAt: index, window: shortWindow)
                    let longAverage = meanClose(in: candles, endingAt: index, window: longWindow)

                    if let previousShort, let previousLong {
                        let crossesUp = previousShort <= previousLong && shortAverage > longAverage
                        let crossesDown = previousShort >= previousLong && shortAverage < longAverage

                        if crossesUp, quantity == 0 {
                            buyAll(
                                candle: candle,
                                settings: settings,
                                reason: String(localized: "trade.reason.cross_up"),
                                cash: &cash,
                                quantity: &quantity,
                                trades: &trades
                            )
                        } else if crossesDown, quantity > 0 {
                            sellAll(
                                candle: candle,
                                settings: settings,
                                reason: String(localized: "trade.reason.cross_down"),
                                cash: &cash,
                                quantity: &quantity,
                                trades: &trades
                            )
                        }
                    }

                    previousShort = shortAverage
                    previousLong = longAverage
                }

            case let .breakout(entryWindow, exitWindow):
                if index >= entryWindow {
                    let entryStart = index - entryWindow
                    let previousHigh = candles[entryStart..<index].map(\.high).max() ?? candle.high
                    let exitStart = max(0, index - exitWindow)
                    let previousLow = candles[exitStart..<index].map(\.low).min() ?? candle.low

                    if quantity == 0, candle.close > previousHigh {
                        buyAll(
                            candle: candle,
                            settings: settings,
                            reason: String(localized: "trade.reason.breakout"),
                            cash: &cash,
                            quantity: &quantity,
                            trades: &trades
                        )
                    } else if quantity > 0, candle.close < previousLow {
                        sellAll(
                            candle: candle,
                            settings: settings,
                            reason: String(localized: "trade.reason.breakdown"),
                            cash: &cash,
                            quantity: &quantity,
                            trades: &trades
                        )
                    }
                }
            }

            equityCurve.append(
                EquityPoint(
                    date: candle.date,
                    strategyValue: cash + Double(quantity) * candle.close,
                    benchmarkValue: settings.initialCapital * candle.close / firstClose
                )
            )
        }

        if quantity > 0, let last = candles.last {
            sellAll(
                candle: last,
                settings: settings,
                reason: String(localized: "trade.reason.period_end"),
                cash: &cash,
                quantity: &quantity,
                trades: &trades
            )
            if let lastPoint = equityCurve.last {
                equityCurve[equityCurve.count - 1] = EquityPoint(
                    date: lastPoint.date,
                    strategyValue: cash,
                    benchmarkValue: lastPoint.benchmarkValue
                )
            }
        }

        let finalValue = equityCurve.last?.strategyValue ?? settings.initialCapital
        let cumulativeReturn = finalValue / settings.initialCapital - 1
        let benchmarkReturn = (candles.last?.close ?? firstClose) / firstClose - 1
        let riskMetrics = riskMetrics(
            values: equityCurve.map(\.strategyValue),
            cumulativeReturn: cumulativeReturn,
            startDate: candles[0].date,
            endDate: candles[candles.count - 1].date,
            calendar: calendar
        )

        return BacktestResult(
            security: security,
            strategy: strategy,
            settings: settings,
            candles: candles,
            trades: trades,
            equityCurve: equityCurve,
            finalValue: finalValue,
            cumulativeReturn: cumulativeReturn,
            benchmarkReturn: benchmarkReturn,
            maxDrawdown: maximumDrawdown(equityCurve.map(\.strategyValue)),
            annualizedReturn: riskMetrics.annualizedReturn,
            annualizedVolatility: riskMetrics.annualizedVolatility,
            sharpeRatio: riskMetrics.sharpeRatio
        )
    }

    private static func riskMetrics(
        values: [Double],
        cumulativeReturn: Double,
        startDate: Date,
        endDate: Date,
        calendar: Calendar
    ) -> (annualizedReturn: Double, annualizedVolatility: Double, sharpeRatio: Double?) {
        let elapsedDays = max(calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0, 1)
        let years = Double(elapsedDays) / 365.2425
        let growth = max(1 + cumulativeReturn, 0)
        let annualizedReturn = growth > 0 ? pow(growth, 1 / years) - 1 : -1

        let returns = zip(values.dropFirst(), values).compactMap { current, previous -> Double? in
            guard previous > 0 else { return nil }
            return current / previous - 1
        }
        guard returns.count > 1 else {
            return (annualizedReturn, 0, nil)
        }

        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(returns.count - 1)
        let dailyDeviation = sqrt(max(variance, 0))
        let annualizedVolatility = dailyDeviation * sqrt(252)
        let sharpeRatio = dailyDeviation > 0 ? mean / dailyDeviation * sqrt(252) : nil
        return (annualizedReturn, annualizedVolatility, sharpeRatio)
    }

    private static func meanClose(in candles: [Candle], endingAt index: Int, window: Int) -> Double {
        let start = index - window + 1
        return candles[start...index].reduce(0) { $0 + $1.close } / Double(window)
    }

    private static func monthKey(for date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month], from: date)
    }

    private static func buy(
        amount: Double,
        candle: Candle,
        settings: BacktestSettings,
        reason: String,
        cash: inout Double,
        quantity: inout Int,
        trades: inout [SimulatedTrade]
    ) {
        let executionPrice = candle.close * (1 + settings.slippageRate)
        let unitCost = executionPrice * (1 + settings.commissionRate)
        let purchasable = Int(floor(min(amount, cash) / unitCost))
        guard purchasable > 0 else { return }
        let gross = executionPrice * Double(purchasable)
        let fee = gross * settings.commissionRate
        cash -= gross + fee
        quantity += purchasable
        trades.append(
            SimulatedTrade(
                id: UUID(),
                date: candle.date,
                side: .buy,
                price: executionPrice,
                quantity: purchasable,
                fee: fee,
                reason: reason
            )
        )
    }

    private static func buyAll(
        candle: Candle,
        settings: BacktestSettings,
        reason: String,
        cash: inout Double,
        quantity: inout Int,
        trades: inout [SimulatedTrade]
    ) {
        let executionPrice = candle.close * (1 + settings.slippageRate)
        let unitCost = executionPrice * (1 + settings.commissionRate)
        let purchasable = Int(floor(cash / unitCost))
        guard purchasable > 0 else { return }
        let gross = executionPrice * Double(purchasable)
        let fee = gross * settings.commissionRate
        cash -= gross + fee
        quantity += purchasable
        trades.append(
            SimulatedTrade(
                id: UUID(),
                date: candle.date,
                side: .buy,
                price: executionPrice,
                quantity: purchasable,
                fee: fee,
                reason: reason
            )
        )
    }

    private static func sellAll(
        candle: Candle,
        settings: BacktestSettings,
        reason: String,
        cash: inout Double,
        quantity: inout Int,
        trades: inout [SimulatedTrade]
    ) {
        let executionPrice = candle.close * (1 - settings.slippageRate)
        let gross = executionPrice * Double(quantity)
        let fee = gross * settings.commissionRate
        cash += gross - fee
        trades.append(
            SimulatedTrade(
                id: UUID(),
                date: candle.date,
                side: .sell,
                price: executionPrice,
                quantity: quantity,
                fee: fee,
                reason: reason
            )
        )
        quantity = 0
    }

    private static func maximumDrawdown(_ values: [Double]) -> Double {
        var peak = values.first ?? 0
        var maximum = 0.0
        for value in values {
            peak = max(peak, value)
            guard peak > 0 else { continue }
            maximum = max(maximum, (peak - value) / peak)
        }
        return maximum
    }
}
