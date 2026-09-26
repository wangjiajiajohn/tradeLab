import SwiftUI
import UniformTypeIdentifiers

struct TradeJournalView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingEntry = false
    @State private var showingImporter = false
    @State private var importMessage: String?
    @State private var importError: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Button {
                        showingEntry = true
                    } label: {
                        Label("trades.add", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showingImporter = true
                    } label: {
                        Label("trades.import", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)

                if !model.journalTrades.isEmpty,
                   let exportURL = CSVExports.trades(model.journalTrades) {
                    ShareLink(item: exportURL) {
                        Label("trades.export", systemImage: "square.and.arrow.up")
                    }
                }

                Text("trades.import.help")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !model.journalTrades.isEmpty {
                analysisSections
                Section("trades.records") {
                    ForEach(model.journalTrades) { trade in
                        TradeRow(trade: trade)
                    }
                    .onDelete(perform: model.deleteJournalTrades)
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "trades.empty.title",
                        systemImage: "tray.and.arrow.down",
                        description: Text("trades.empty.description")
                    )
                }
            }
        }
        .sheet(isPresented: $showingEntry) {
            TradeEntryView()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importCSV(result)
        }
        .alert("trades.import.result", isPresented: Binding(
            get: { importMessage != nil || importError != nil },
            set: { if !$0 { importMessage = nil; importError = nil } }
        )) {
            Button("action.done") { importMessage = nil; importError = nil }
        } message: {
            Text(importError ?? importMessage ?? "")
        }
    }

    @ViewBuilder
    private var analysisSections: some View {
        let analysis = model.journalAnalysis
        Section("trades.analysis") {
            ForEach(analysis.summaries) { summary in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(summary.currency).font(.headline)
                        Spacer()
                        Text(summary.realizedProfit, format: .currency(code: summary.currency))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(summary.realizedProfit >= 0 ? .green : .red)
                    }
                    HStack {
                        metric("trades.buy_amount", summary.buyAmount, summary.currency)
                        metric("trades.sell_amount", summary.sellAmount, summary.currency)
                        metric("trades.fees", summary.fees, summary.currency)
                    }
                }
                .padding(.vertical, 4)
            }
        }

        if !analysis.positions.isEmpty {
            Section("trades.open_positions") {
                ForEach(analysis.positions) { position in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(position.quantity, format: .number.precision(.fractionLength(0...4)))
                            Text(position.averageCost, format: .currency(code: position.currency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(position.symbol).font(.headline)
                    }
                }
            }
        }

        if !analysis.oversoldSymbols.isEmpty {
            Section("trades.data_issues") {
                Label {
                    Text(String(
                        format: String(localized: "trades.oversold_format"),
                        analysis.oversoldSymbols.joined(separator: ", ")
                    ))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: Double, _ currency: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: currency))
                .font(.caption.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func importCSV(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let parsed = try TradeCSVImporter.parse(data: Data(contentsOf: url))
            model.addJournalTrades(parsed.trades)
            importMessage = String(
                format: String(localized: "trades.import.success_format"),
                parsed.trades.count,
                parsed.rejectedRows
            )
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct TradeRow: View {
    let trade: JournalTrade

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(trade.symbol).font(.headline)
                    Text(trade.side == .buy ? "trades.buy" : "trades.sell")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trade.side == .buy ? .green : .red)
                }
                Text(trade.date, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(trade.price, format: .currency(code: trade.currency))
                    .font(.subheadline.monospacedDigit())
                Text(trade.quantity, format: .number.precision(.fractionLength(0...4)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct TradeEntryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var symbol = ""
    @State private var side: TradeSide = .buy
    @State private var quantity = ""
    @State private var price = ""
    @State private var fee = ""
    @State private var currency = "USD"
    @State private var note = ""

    private var parsedQuantity: Double? { Double(quantity.replacingOccurrences(of: ",", with: "")) }
    private var parsedPrice: Double? { Double(price.replacingOccurrences(of: ",", with: "")) }
    private var isValid: Bool {
        !symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedQuantity ?? 0) > 0
            && (parsedPrice ?? 0) > 0
            && !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("trades.order") {
                    TextField("trades.symbol", text: $symbol)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("trades.side", selection: $side) {
                        Text("trades.buy").tag(TradeSide.buy)
                        Text("trades.sell").tag(TradeSide.sell)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("trades.date", selection: $date)
                }
                Section("trades.execution") {
                    TextField("trades.quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                    TextField("trades.price", text: $price)
                        .keyboardType(.decimalPad)
                    TextField("trades.fee_optional", text: $fee)
                        .keyboardType(.decimalPad)
                    TextField("trades.currency", text: $currency)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section("trades.note_optional") {
                    TextField("trades.note", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("trades.add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("strategies.save") {
                        model.addJournalTrade(JournalTrade(
                            date: date,
                            symbol: symbol,
                            side: side,
                            quantity: parsedQuantity ?? 0,
                            price: parsedPrice ?? 0,
                            fee: Double(fee.replacingOccurrences(of: ",", with: "")) ?? 0,
                            currency: currency,
                            note: note
                        ))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
