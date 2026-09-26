import Foundation

struct BacktestDiagnostic: Identifiable, Sendable {
    enum Severity: Sendable {
        case critical
        case warning
        case information
    }

    enum Kind: Sendable {
        case risingMarketDCA(gap: Double)
        case underperformed(gap: Double)
        case noDownsideProtection(drawdown: Double)
        case deepDrawdown(drawdown: Double)
        case tooFewSignals(entries: Int)
        case whipsaw(losses: Int, closedTrades: Int)
        case missedTrend(exposure: Double)
        case highCosts(ratio: Double)
        case shortSample(days: Int)
        case noClearEdge(gap: Double)
        case noObviousIssue
    }

    let id: String
    let severity: Severity
    let kind: Kind
}

enum BacktestDiagnostics {
    static func analyze(_ result: BacktestResult) -> [BacktestDiagnostic] {
        var items: [BacktestDiagnostic] = []
        let gap = result.excessReturn
        let days = sampleDays(result)

        if case .monthlyDCA = result.strategy.rule,
           result.benchmarkReturn > 0.05,
           gap < -0.02 {
            items.append(.init(
                id: "rising-market-dca",
                severity: abs(gap) >= 0.10 ? .critical : .warning,
                kind: .risingMarketDCA(gap: abs(gap))
            ))
        } else if gap < -0.02 {
            items.append(.init(
                id: "underperformed",
                severity: abs(gap) >= 0.10 ? .critical : .warning,
                kind: .underperformed(gap: abs(gap))
            ))
        } else if abs(gap) < 0.01 {
            items.append(.init(
                id: "no-clear-edge",
                severity: .information,
                kind: .noClearEdge(gap: gap)
            ))
        }

        let benchmarkDrawdown = maximumDrawdown(result.equityCurve.map(\.benchmarkValue))
        if case .buyAndHold = result.strategy.rule, result.maxDrawdown >= 0.08 {
            items.append(.init(
                id: "no-downside-protection",
                severity: result.maxDrawdown >= 0.20 ? .critical : .warning,
                kind: .noDownsideProtection(drawdown: result.maxDrawdown)
            ))
        } else if result.maxDrawdown >= 0.15 {
            items.append(.init(
                id: "deep-drawdown",
                severity: result.maxDrawdown >= 0.25 ? .critical : .warning,
                kind: .deepDrawdown(drawdown: result.maxDrawdown)
            ))
        } else if benchmarkDrawdown >= 0.10,
                  result.maxDrawdown >= benchmarkDrawdown * 0.9 {
            items.append(.init(
                id: "limited-protection",
                severity: .warning,
                kind: .noDownsideProtection(drawdown: result.maxDrawdown)
            ))
        }

        switch result.strategy.rule {
        case .dualMovingAverage, .breakout:
            let entries = result.trades.filter { $0.side == .buy }.count
            if entries < 2 {
                items.append(.init(
                    id: "few-signals",
                    severity: .warning,
                    kind: .tooFewSignals(entries: entries)
                ))
            } else {
                let closedReturns = closedTradeReturns(result.trades)
                let losses = closedReturns.filter { $0 < 0 }.count
                if closedReturns.count >= 3, losses * 2 >= closedReturns.count {
                    items.append(.init(
                        id: "whipsaw",
                        severity: .warning,
                        kind: .whipsaw(losses: losses, closedTrades: closedReturns.count)
                    ))
                }

                let exposure = investedRatio(result)
                if result.benchmarkReturn > 0.10, gap < -0.02, exposure < 0.60 {
                    items.append(.init(
                        id: "missed-trend",
                        severity: .warning,
                        kind: .missedTrend(exposure: exposure)
                    ))
                }
            }
        case .buyAndHold, .monthlyDCA:
            break
        }

        let feeRatio = result.totalFees / max(result.settings.initialCapital, 1)
        if feeRatio >= 0.01 {
            items.append(.init(
                id: "high-costs",
                severity: .warning,
                kind: .highCosts(ratio: feeRatio)
            ))
        }

        if days < 504 {
            items.append(.init(
                id: "short-sample",
                severity: .information,
                kind: .shortSample(days: days)
            ))
        }

        if items.isEmpty {
            items.append(.init(
                id: "no-obvious-issue",
                severity: .information,
                kind: .noObviousIssue
            ))
        }

        return Array(items.prefix(4))
    }

    private static func sampleDays(_ result: BacktestResult) -> Int {
        guard let first = result.candles.first?.date,
              let last = result.candles.last?.date
        else { return 0 }
        return max(Calendar(identifier: .gregorian).dateComponents([.day], from: first, to: last).day ?? 0, 0)
    }

    private static func maximumDrawdown(_ values: [Double]) -> Double {
        var peak = values.first ?? 0
        var drawdown = 0.0
        for value in values {
            peak = max(peak, value)
            guard peak > 0 else { continue }
            drawdown = max(drawdown, (peak - value) / peak)
        }
        return drawdown
    }

    private static func closedTradeReturns(_ trades: [SimulatedTrade]) -> [Double] {
        var entryCost: Double?
        var returns: [Double] = []
        for trade in trades.sorted(by: { $0.date < $1.date }) {
            switch trade.side {
            case .buy:
                entryCost = trade.price * Double(trade.quantity) + trade.fee
            case .sell:
                guard let cost = entryCost, cost > 0 else { continue }
                let proceeds = trade.price * Double(trade.quantity) - trade.fee
                returns.append(proceeds / cost - 1)
                entryCost = nil
            }
        }
        return returns
    }

    private static func investedRatio(_ result: BacktestResult) -> Double {
        guard !result.candles.isEmpty else { return 0 }
        let tradesByDay = Dictionary(grouping: result.trades) {
            Calendar(identifier: .gregorian).startOfDay(for: $0.date)
        }
        var quantity = 0
        var investedDays = 0
        for candle in result.candles {
            let day = Calendar(identifier: .gregorian).startOfDay(for: candle.date)
            for trade in tradesByDay[day] ?? [] {
                quantity += trade.side == .buy ? trade.quantity : -trade.quantity
            }
            if quantity > 0 { investedDays += 1 }
        }
        return Double(investedDays) / Double(result.candles.count)
    }
}
