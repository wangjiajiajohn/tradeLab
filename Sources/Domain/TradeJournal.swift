import Foundation

struct JournalTrade: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let date: Date
    let symbol: String
    let side: TradeSide
    let quantity: Double
    let price: Double
    let fee: Double
    let currency: String
    let note: String

    init(
        id: UUID = UUID(),
        date: Date,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double,
        fee: Double = 0,
        currency: String,
        note: String = ""
    ) {
        self.id = id
        self.date = date
        self.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.side = side
        self.quantity = quantity
        self.price = price
        self.fee = fee
        self.currency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TradeCurrencySummary: Identifiable, Hashable, Sendable {
    var id: String { currency }
    let currency: String
    let realizedProfit: Double
    let buyAmount: Double
    let sellAmount: Double
    let fees: Double
}

struct OpenPosition: Identifiable, Hashable, Sendable {
    var id: String { "\(symbol)-\(currency)" }
    let symbol: String
    let currency: String
    let quantity: Double
    let averageCost: Double
}

struct TradeJournalAnalysis: Hashable, Sendable {
    let summaries: [TradeCurrencySummary]
    let positions: [OpenPosition]
    let oversoldSymbols: [String]
}

enum TradeJournalAnalyzer {
    private struct Lot {
        var quantity: Double
        let unitCost: Double
    }

    static func analyze(_ trades: [JournalTrade]) -> TradeJournalAnalysis {
        let sorted = trades.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.id.uuidString < rhs.id.uuidString : lhs.date < rhs.date
        }
        var lots: [String: [Lot]] = [:]
        var realized: [String: Double] = [:]
        var buyAmounts: [String: Double] = [:]
        var sellAmounts: [String: Double] = [:]
        var fees: [String: Double] = [:]
        var oversold = Set<String>()

        for trade in sorted {
            let key = "\(trade.symbol)|\(trade.currency)"
            fees[trade.currency, default: 0] += trade.fee
            switch trade.side {
            case .buy:
                let gross = trade.price * trade.quantity
                buyAmounts[trade.currency, default: 0] += gross
                let unitCost = trade.quantity > 0 ? (gross + trade.fee) / trade.quantity : trade.price
                lots[key, default: []].append(Lot(quantity: trade.quantity, unitCost: unitCost))
            case .sell:
                let gross = trade.price * trade.quantity
                sellAmounts[trade.currency, default: 0] += gross
                var remaining = trade.quantity
                var costBasis = 0.0
                while remaining > 0.000_000_1, !(lots[key] ?? []).isEmpty {
                    var first = lots[key]![0]
                    let matched = min(first.quantity, remaining)
                    costBasis += matched * first.unitCost
                    first.quantity -= matched
                    remaining -= matched
                    if first.quantity <= 0.000_000_1 {
                        lots[key]!.removeFirst()
                    } else {
                        lots[key]![0] = first
                    }
                }
                if remaining > 0.000_000_1 { oversold.insert(trade.symbol) }
                let matchedQuantity = trade.quantity - remaining
                let allocatedFee = trade.quantity > 0 ? trade.fee * matchedQuantity / trade.quantity : 0
                realized[trade.currency, default: 0] += matchedQuantity * trade.price - allocatedFee - costBasis
            }
        }

        let currencies = Set(buyAmounts.keys)
            .union(sellAmounts.keys)
            .union(fees.keys)
            .union(realized.keys)
        let summaries = currencies.sorted().map { currency in
            TradeCurrencySummary(
                currency: currency,
                realizedProfit: realized[currency, default: 0],
                buyAmount: buyAmounts[currency, default: 0],
                sellAmount: sellAmounts[currency, default: 0],
                fees: fees[currency, default: 0]
            )
        }
        let positions = lots.compactMap { key, remainingLots -> OpenPosition? in
            let quantity = remainingLots.reduce(0) { $0 + $1.quantity }
            guard quantity > 0.000_000_1 else { return nil }
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let totalCost = remainingLots.reduce(0) { $0 + $1.quantity * $1.unitCost }
            return OpenPosition(symbol: parts[0], currency: parts[1], quantity: quantity, averageCost: totalCost / quantity)
        }
        .sorted { $0.symbol < $1.symbol }

        return TradeJournalAnalysis(
            summaries: summaries,
            positions: positions,
            oversoldSymbols: oversold.sorted()
        )
    }
}
