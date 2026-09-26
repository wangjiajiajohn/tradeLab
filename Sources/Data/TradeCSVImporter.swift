import Foundation

struct TradeCSVImportResult: Sendable {
    let trades: [JournalTrade]
    let rejectedRows: Int
}

enum TradeCSVImportError: LocalizedError {
    case unreadable
    case missingColumns
    case noValidRows

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "trades.import.unreadable")
        case .missingColumns: String(localized: "trades.import.missing_columns")
        case .noValidRows: String(localized: "trades.import.no_valid_rows")
        }
    }
}

enum TradeCSVImporter {
    private enum Field: CaseIterable {
        case date, symbol, side, quantity, price, fee, currency, note

        var aliases: Set<String> {
            switch self {
            case .date: ["date", "time", "datetime", "tradedate", "成交日期", "交易日期", "成交时间", "交易時間"]
            case .symbol: ["symbol", "code", "ticker", "security", "股票代码", "股票代碼", "证券代码", "證券代碼"]
            case .side: ["side", "action", "direction", "buysell", "买卖", "買賣", "方向"]
            case .quantity: ["quantity", "qty", "shares", "volume", "数量", "數量", "成交数量", "成交數量"]
            case .price: ["price", "tradeprice", "成交价", "成交價", "价格", "價格"]
            case .fee: ["fee", "fees", "commission", "手续费", "手續費", "佣金"]
            case .currency: ["currency", "ccy", "币种", "幣種", "货币", "貨幣"]
            case .note: ["note", "memo", "remark", "备注", "備註"]
            }
        }
    }

    static func parse(data: Data) throws -> TradeCSVImportResult {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .unicode)
        else { throw TradeCSVImportError.unreadable }

        let rows = parseRows(text)
        guard let header = rows.first, header.count > 1 else { throw TradeCSVImportError.unreadable }
        let normalized = header.map(normalize)
        var indexes: [Field: Int] = [:]
        for field in Field.allCases {
            if let index = normalized.firstIndex(where: { field.aliases.contains($0) }) {
                indexes[field] = index
            }
        }
        guard indexes[.date] != nil, indexes[.symbol] != nil, indexes[.side] != nil,
              indexes[.quantity] != nil, indexes[.price] != nil
        else { throw TradeCSVImportError.missingColumns }

        var trades: [JournalTrade] = []
        var rejected = 0
        for row in rows.dropFirst() where row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            guard let date = value(.date, row, indexes).flatMap(parseDate),
                  let symbol = value(.symbol, row, indexes), !symbol.isEmpty,
                  let side = value(.side, row, indexes).flatMap(parseSide),
                  let quantity = value(.quantity, row, indexes).flatMap(parseNumber), quantity > 0,
                  let price = value(.price, row, indexes).flatMap(parseNumber), price > 0
            else { rejected += 1; continue }
            trades.append(JournalTrade(
                date: date,
                symbol: symbol,
                side: side,
                quantity: quantity,
                price: price,
                fee: value(.fee, row, indexes).flatMap(parseNumber) ?? 0,
                currency: value(.currency, row, indexes).flatMap { $0.isEmpty ? nil : $0 } ?? "USD",
                note: value(.note, row, indexes) ?? ""
            ))
        }
        guard !trades.isEmpty else { throw TradeCSVImportError.noValidRows }
        return TradeCSVImportResult(trades: trades, rejectedRows: rejected)
    }

    private static func value(_ field: Field, _ row: [String], _ indexes: [Field: Int]) -> String? {
        guard let index = indexes[field], row.indices.contains(index) else { return nil }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func parseNumber(_ value: String) -> Double? {
        let cleaned = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "HK$", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private static func parseSide(_ value: String) -> TradeSide? {
        switch normalize(value) {
        case "buy", "b", "买入", "買入": .buy
        case "sell", "s", "卖出", "賣出": .sell
        default: nil
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss", "yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted, index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                row.append(field); field = ""
            } else if character == "\n", !quoted {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
