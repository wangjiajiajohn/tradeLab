import Foundation

struct BacktestDiagnostic: Identifiable, Sendable {
    enum Severity: Sendable, Equatable {
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

struct BacktestCurveProfile: Sendable {
    enum Trend: Sendable {
        case rising
        case falling
        case sideways
    }

    let trend: Trend
    let returnRate: Double
    let annualizedVolatility: Double
    let efficiency: Double
    let maximumDrawdown: Double
    let drawdownPeak: Date?
    let drawdownTrough: Date?
}

struct BacktestOperationFinding: Identifiable, Sendable {
    enum Kind: Sendable {
        case buyBeforeDecline(date: Date, decline: Double, tradingDays: Int)
        case sellBeforeRise(date: Date, rise: Double, tradingDays: Int)
        case losingRoundTrip(entry: Date, exit: Date, loss: Double)
    }

    let id: String
    let severity: BacktestDiagnostic.Severity
    let kind: Kind
}

struct BacktestOptimization: Identifiable, Sendable {
    enum Kind: Sendable {
        case compareFrontLoadedEntry
        case addTrendConfirmation
        case reduceTrendLag
        case confirmBreakout
        case addRiskExit
        case extendSample
        case crossValidate
    }

    let id: String
    let kind: Kind
}

struct BacktestAnalysisReport: Sendable {
    let curve: BacktestCurveProfile
    let diagnostics: [BacktestDiagnostic]
    let operationFindings: [BacktestOperationFinding]
    let optimizations: [BacktestOptimization]
}

enum BacktestDiagnostics {
    static func report(_ result: BacktestResult) -> BacktestAnalysisReport {
        let diagnostics = analyze(result)
        let operations = operationFindings(result)
        return BacktestAnalysisReport(
            curve: curveProfile(result.candles),
            diagnostics: diagnostics,
            operationFindings: operations,
            optimizations: optimizations(
                for: result,
                diagnostics: diagnostics,
                operations: operations
            )
        )
    }

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

    private static func curveProfile(_ candles: [Candle]) -> BacktestCurveProfile {
        let closes = candles.map(\.close)
        let first = closes.first ?? 0
        let last = closes.last ?? first
        let returnRate = first > 0 ? last / first - 1 : 0
        let path = zip(closes.dropFirst(), closes).reduce(0) { partial, pair in
            partial + abs(pair.0 - pair.1)
        }
        let efficiency = path > 0 ? abs(last - first) / path : 0
        let returns = zip(closes.dropFirst(), closes).compactMap { current, previous -> Double? in
            guard previous > 0 else { return nil }
            return current / previous - 1
        }
        let mean = returns.isEmpty ? 0 : returns.reduce(0, +) / Double(returns.count)
        let variance = returns.count > 1
            ? returns.reduce(0) { $0 + pow($1 - mean, 2) } / Double(returns.count - 1)
            : 0
        let volatility = sqrt(max(variance, 0)) * sqrt(252)
        let drawdown = drawdownPeriod(candles)

        let trend: BacktestCurveProfile.Trend
        if returnRate >= 0.08 { trend = .rising }
        else if returnRate <= -0.08 { trend = .falling }
        else { trend = .sideways }

        return BacktestCurveProfile(
            trend: trend,
            returnRate: returnRate,
            annualizedVolatility: volatility,
            efficiency: efficiency,
            maximumDrawdown: drawdown.value,
            drawdownPeak: drawdown.peak,
            drawdownTrough: drawdown.trough
        )
    }

    private static func drawdownPeriod(_ candles: [Candle]) -> (value: Double, peak: Date?, trough: Date?) {
        guard let first = candles.first else { return (0, nil, nil) }
        var peakValue = first.close
        var peakDate = first.date
        var worst = 0.0
        var worstPeak: Date?
        var worstTrough: Date?
        for candle in candles {
            if candle.close > peakValue {
                peakValue = candle.close
                peakDate = candle.date
            }
            guard peakValue > 0 else { continue }
            let drawdown = (peakValue - candle.close) / peakValue
            if drawdown > worst {
                worst = drawdown
                worstPeak = peakDate
                worstTrough = candle.date
            }
        }
        return (worst, worstPeak, worstTrough)
    }

    private static func operationFindings(_ result: BacktestResult) -> [BacktestOperationFinding] {
        let candles = result.candles
        let indexByDate = Dictionary(uniqueKeysWithValues: candles.enumerated().map { ($1.date, $0) })
        let horizon = 20
        var findings: [BacktestOperationFinding] = []

        let riskyBuys = result.trades.compactMap { trade -> BacktestOperationFinding? in
            guard trade.side == .buy,
                  let index = indexByDate[trade.date],
                  index + 1 < candles.count
            else { return nil }
            let end = min(index + horizon, candles.count - 1)
            let futureLow = candles[(index + 1)...end].map(\.close).min() ?? trade.price
            let decline = futureLow / trade.price - 1
            guard decline <= -0.05 else { return nil }
            return BacktestOperationFinding(
                id: "buy-\(trade.id.uuidString)",
                severity: decline <= -0.12 ? .critical : .warning,
                kind: .buyBeforeDecline(date: trade.date, decline: abs(decline), tradingDays: end - index)
            )
        }
        if let worstBuy = riskyBuys.max(by: { operationImpact($0) < operationImpact($1) }) {
            findings.append(worstBuy)
        }

        switch result.strategy.rule {
        case .dualMovingAverage, .breakout:
            let prematureSells = result.trades.compactMap { trade -> BacktestOperationFinding? in
                guard trade.side == .sell,
                      let index = indexByDate[trade.date],
                      index + 1 < candles.count
                else { return nil }
                let end = min(index + horizon, candles.count - 1)
                let futureHigh = candles[(index + 1)...end].map(\.close).max() ?? trade.price
                let rise = futureHigh / trade.price - 1
                guard rise >= 0.05 else { return nil }
                return BacktestOperationFinding(
                    id: "sell-\(trade.id.uuidString)",
                    severity: rise >= 0.12 ? .critical : .warning,
                    kind: .sellBeforeRise(date: trade.date, rise: rise, tradingDays: end - index)
                )
            }
            if let worstSell = prematureSells.max(by: { operationImpact($0) < operationImpact($1) }) {
                findings.append(worstSell)
            }
            if let worstLoss = worstRoundTrip(result.trades) {
                findings.append(worstLoss)
            }
        case .buyAndHold, .monthlyDCA:
            break
        }

        return Array(findings.sorted { operationImpact($0) > operationImpact($1) }.prefix(3))
    }

    private static func operationImpact(_ finding: BacktestOperationFinding) -> Double {
        switch finding.kind {
        case let .buyBeforeDecline(_, decline, _): decline
        case let .sellBeforeRise(_, rise, _): rise
        case let .losingRoundTrip(_, _, loss): loss
        }
    }

    private static func worstRoundTrip(_ trades: [SimulatedTrade]) -> BacktestOperationFinding? {
        var entry: SimulatedTrade?
        var findings: [BacktestOperationFinding] = []
        for trade in trades.sorted(by: { $0.date < $1.date }) {
            if trade.side == .buy {
                entry = trade
            } else if let buy = entry {
                let cost = buy.price * Double(buy.quantity) + buy.fee
                let proceeds = trade.price * Double(trade.quantity) - trade.fee
                let tradeReturn = cost > 0 ? proceeds / cost - 1 : 0
                if tradeReturn <= -0.03 {
                    findings.append(.init(
                        id: "round-trip-\(buy.id.uuidString)",
                        severity: tradeReturn <= -0.10 ? .critical : .warning,
                        kind: .losingRoundTrip(entry: buy.date, exit: trade.date, loss: abs(tradeReturn))
                    ))
                }
                entry = nil
            }
        }
        return findings.max(by: { operationImpact($0) < operationImpact($1) })
    }

    private static func optimizations(
        for result: BacktestResult,
        diagnostics: [BacktestDiagnostic],
        operations: [BacktestOperationFinding]
    ) -> [BacktestOptimization] {
        let ids = Set(diagnostics.map(\.id))
        var kinds: [BacktestOptimization.Kind] = []

        switch result.strategy.rule {
        case .monthlyDCA:
            if ids.contains("rising-market-dca") { kinds.append(.compareFrontLoadedEntry) }
        case .dualMovingAverage:
            if ids.contains("whipsaw") { kinds.append(.addTrendConfirmation) }
            if ids.contains("missed-trend") { kinds.append(.reduceTrendLag) }
        case .breakout:
            if ids.contains("whipsaw") { kinds.append(.confirmBreakout) }
            if ids.contains("missed-trend") { kinds.append(.reduceTrendLag) }
        case .buyAndHold:
            break
        }

        if ids.contains("deep-drawdown") || ids.contains("limited-protection") || ids.contains("no-downside-protection") || operations.contains(where: {
            if case .buyBeforeDecline = $0.kind { return true }
            return false
        }) {
            kinds.append(.addRiskExit)
        }
        if ids.contains("short-sample") { kinds.append(.extendSample) }
        if kinds.isEmpty { kinds.append(.crossValidate) }

        var seen = Set<String>()
        return kinds.compactMap { kind in
            let id = optimizationID(kind)
            guard seen.insert(id).inserted else { return nil }
            return BacktestOptimization(id: id, kind: kind)
        }.prefix(3).map { $0 }
    }

    private static func optimizationID(_ kind: BacktestOptimization.Kind) -> String {
        switch kind {
        case .compareFrontLoadedEntry: "compare-front-loaded"
        case .addTrendConfirmation: "add-trend-confirmation"
        case .reduceTrendLag: "reduce-trend-lag"
        case .confirmBreakout: "confirm-breakout"
        case .addRiskExit: "add-risk-exit"
        case .extendSample: "extend-sample"
        case .crossValidate: "cross-validate"
        }
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
