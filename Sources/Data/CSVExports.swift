import Foundation

enum CSVExports {
    static func backtests(_ records: [BacktestRecord]) -> URL? {
        var rows = [[
            "created_at", "symbol", "security", "strategy", "currency", "initial_capital",
            "final_value", "return", "benchmark_return", "max_drawdown", "annualized_return",
            "annualized_volatility", "sharpe_ratio", "total_fees", "trade_count"
        ]]
        let formatter = ISO8601DateFormatter()
        rows += records.map { record in
            [
                formatter.string(from: record.createdAt), record.securitySymbol, record.securityName,
                record.strategyName, record.currency, String(record.settings.initialCapital),
                String(record.finalValue), String(record.cumulativeReturn), String(record.benchmarkReturn),
                String(record.maxDrawdown), Self.value(record.annualizedReturn), Self.value(record.annualizedVolatility),
                Self.value(record.sharpeRatio), Self.value(record.totalFees), String(record.tradeCount)
            ]
        }
        return write(rows, name: "TradeLab-Backtests.csv")
    }

    private static func value(_ number: Double?) -> String { number.map { String($0) } ?? "" }

    static func trades(_ trades: [JournalTrade]) -> URL? {
        var rows = [["date", "symbol", "side", "quantity", "price", "fee", "currency", "note"]]
        let formatter = ISO8601DateFormatter()
        rows += trades.map { trade in
            [
                formatter.string(from: trade.date), trade.symbol, trade.side.rawValue,
                String(trade.quantity), String(trade.price), String(trade.fee), trade.currency, trade.note
            ]
        }
        return write(rows, name: "TradeLab-Trades.csv")
    }

    private static func write(_ rows: [[String]], name: String) -> URL? {
        let text = rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
