import SwiftUI

struct ReviewView: View {
    private enum ReviewMode: String, CaseIterable, Identifiable {
        case backtests
        case trades
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @State private var mode: ReviewMode = .backtests
    @State private var isSelectingForComparison = false
    @State private var selectedRecordIDs: [UUID] = []
    @State private var showingComparison = false

    private var selectedRecords: [BacktestRecord] {
        selectedRecordIDs.compactMap { id in
            model.backtestHistory.first { $0.id == id }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("review.mode", selection: $mode) {
                    Text("review.mode.backtests").tag(ReviewMode.backtests)
                    Text("review.mode.trades").tag(ReviewMode.trades)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if mode == .trades {
                    TradeJournalView()
                } else if model.backtestHistory.isEmpty {
                    ContentUnavailableView(
                        "review.empty.title",
                        systemImage: "book.pages",
                        description: Text("review.empty.description")
                    )
                } else {
                    List(model.backtestHistory) { record in
                        if isSelectingForComparison {
                            Button {
                                toggleSelection(record)
                            } label: {
                                HStack(spacing: 12) {
                                    comparisonIndicator(for: record)
                                    BacktestRecordRow(record: record)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedRecordIDs.count == 2 && !selectedRecordIDs.contains(record.id))
                        } else {
                            NavigationLink {
                                BacktestRecordDetail(record: record)
                            } label: {
                                BacktestRecordRow(record: record)
                            }
                        }
                    }
                }
            }
            .navigationTitle("tab.review")
            .toolbar {
                if mode == .backtests && !model.backtestHistory.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSelectingForComparison ? "action.cancel" : "review.compare") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectingForComparison.toggle()
                                selectedRecordIDs.removeAll()
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if mode == .backtests && isSelectingForComparison {
                    Button {
                        showingComparison = true
                    } label: {
                        Text(String(format: String(localized: "review.compare_selected_format"), selectedRecordIDs.count))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .disabled(selectedRecordIDs.count != 2)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
            .sheet(isPresented: $showingComparison) {
                if selectedRecords.count == 2 {
                    BacktestComparisonView(first: selectedRecords[0], second: selectedRecords[1])
                }
            }
        }
    }

    private func toggleSelection(_ record: BacktestRecord) {
        if selectedRecordIDs.contains(record.id) {
            selectedRecordIDs.removeAll { $0 == record.id }
        } else if selectedRecordIDs.count < 2 {
            selectedRecordIDs.append(record.id)
        }
    }

    private func comparisonIndicator(for record: BacktestRecord) -> some View {
        let selectedIndex = selectedRecords.firstIndex { $0.id == record.id }
        return ZStack {
            Circle()
                .fill(selectedIndex == nil ? Color.clear : Color.accentColor)
                .overlay {
                    Circle()
                        .stroke(selectedIndex == nil ? Color.secondary.opacity(0.45) : Color.clear, lineWidth: 1)
                }
            if let selectedIndex {
                Text("\(selectedIndex + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel(selectedIndex == nil ? Text("review.not_selected") : Text("review.selected"))
    }
}

private struct BacktestRecordRow: View {
    let record: BacktestRecord

    private var returnColor: Color { record.cumulativeReturn >= 0 ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.securityName)
                    .font(.headline)
                Text(record.securitySymbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(record.cumulativeReturn, format: .percent.precision(.fractionLength(1)))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(returnColor)
            }
            HStack {
                Text(record.strategyName)
                    .lineLimit(1)
                Spacer()
                Text(record.createdAt, format: .dateTime.month().day().hour().minute())
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private struct BacktestRecordDetail: View {
    @EnvironmentObject private var model: AppModel
    let record: BacktestRecord

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.securityName)
                        .font(.title2.weight(.semibold))
                    Text("\(record.securitySymbol) · \(record.strategyName)")
                        .foregroundStyle(.secondary)
                    Text(record.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("review.performance") {
                LabeledContent("result.final_value") {
                    Text(record.finalValue, format: .currency(code: record.currency))
                }
                LabeledContent("result.return") {
                    Text(record.cumulativeReturn, format: .percent.precision(.fractionLength(1)))
                        .foregroundStyle(record.cumulativeReturn >= 0 ? .green : .red)
                }
                LabeledContent("result.excess") {
                    Text(record.excessReturn, format: .percent.precision(.fractionLength(1)))
                }
                LabeledContent("result.drawdown") {
                    Text(-record.maxDrawdown, format: .percent.precision(.fractionLength(1)))
                        .foregroundStyle(.orange)
                }
                LabeledContent("result.annualized_return") {
                    optionalPercent(record.annualizedReturn)
                }
                LabeledContent("result.volatility") {
                    optionalPercent(record.annualizedVolatility)
                }
                LabeledContent("result.sharpe") {
                    Text(record.sharpeRatio?.formatted(.number.precision(.fractionLength(2))) ?? "—")
                }
                LabeledContent("result.total_fees") {
                    Text(record.totalFees?.formatted(.currency(code: record.currency)) ?? "—")
                }
                LabeledContent("result.trade_count", value: "\(record.tradeCount)")
            }

            Section("review.assumptions") {
                LabeledContent("settings.period", value: recordPeriod)
                LabeledContent("settings.capital") {
                    Text(record.settings.initialCapital, format: .currency(code: record.currency))
                }
                LabeledContent("settings.commission") {
                    Text(record.settings.commissionRate, format: .percent.precision(.fractionLength(2)))
                }
                LabeledContent("settings.slippage") {
                    Text(record.settings.slippageRate, format: .percent.precision(.fractionLength(2)))
                }
            }

            Section {
                Button {
                    model.restoreConfiguration(from: record)
                } label: {
                    Label("review.restore", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRestoreConfiguration(from: record))
            } footer: {
                Text(LocalizedStringKey(
                    model.canRestoreConfiguration(from: record)
                        ? "review.restore_hint"
                        : "review.restore_unavailable"
                ))
            }
        }
        .navigationTitle("review.detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var recordPeriod: String {
        guard let start = record.settings.startDate,
              let end = record.settings.endDate
        else { return String(localized: "settings.full_period") }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private func optionalPercent(_ value: Double?) -> Text {
        guard let value else { return Text("—") }
        return Text(value, format: .percent.precision(.fractionLength(1)))
    }
}

private struct BacktestComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let first: BacktestRecord
    let second: BacktestRecord

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        comparisonHeader(first, index: 1)
                        Divider()
                        comparisonHeader(second, index: 2)
                    }
                    .padding(.vertical, 6)
                }

                Section("review.performance") {
                    comparisonRow(
                        "result.return",
                        first.cumulativeReturn.formatted(.percent.precision(.fractionLength(1))),
                        second.cumulativeReturn.formatted(.percent.precision(.fractionLength(1))),
                        firstValue: first.cumulativeReturn,
                        secondValue: second.cumulativeReturn,
                        higherIsBetter: true
                    )
                    comparisonRow(
                        "result.excess",
                        first.excessReturn.formatted(.percent.precision(.fractionLength(1))),
                        second.excessReturn.formatted(.percent.precision(.fractionLength(1))),
                        firstValue: first.excessReturn,
                        secondValue: second.excessReturn,
                        higherIsBetter: true
                    )
                    comparisonRow(
                        "result.drawdown",
                        (-first.maxDrawdown).formatted(.percent.precision(.fractionLength(1))),
                        (-second.maxDrawdown).formatted(.percent.precision(.fractionLength(1))),
                        firstValue: first.maxDrawdown,
                        secondValue: second.maxDrawdown,
                        higherIsBetter: false
                    )
                    comparisonRow(
                        "result.annualized_return",
                        percent(first.annualizedReturn),
                        percent(second.annualizedReturn),
                        firstValue: first.annualizedReturn,
                        secondValue: second.annualizedReturn,
                        higherIsBetter: true
                    )
                    comparisonRow(
                        "result.volatility",
                        percent(first.annualizedVolatility),
                        percent(second.annualizedVolatility),
                        firstValue: first.annualizedVolatility,
                        secondValue: second.annualizedVolatility,
                        higherIsBetter: false
                    )
                    comparisonRow(
                        "result.sharpe",
                        number(first.sharpeRatio),
                        number(second.sharpeRatio),
                        firstValue: first.sharpeRatio,
                        secondValue: second.sharpeRatio,
                        higherIsBetter: true
                    )
                    comparisonRow(
                        "result.trade_count",
                        "\(first.tradeCount)",
                        "\(second.tradeCount)"
                    )
                    comparisonRow(
                        "result.final_value",
                        first.finalValue.formatted(.currency(code: first.currency)),
                        second.finalValue.formatted(.currency(code: second.currency))
                    )
                }

                Section("review.assumptions") {
                    comparisonRow("settings.period", period(for: first), period(for: second))
                    comparisonRow(
                        "settings.capital",
                        first.settings.initialCapital.formatted(.currency(code: first.currency)),
                        second.settings.initialCapital.formatted(.currency(code: second.currency))
                    )
                    comparisonRow(
                        "settings.commission",
                        first.settings.commissionRate.formatted(.percent.precision(.fractionLength(2))),
                        second.settings.commissionRate.formatted(.percent.precision(.fractionLength(2)))
                    )
                    comparisonRow(
                        "settings.slippage",
                        first.settings.slippageRate.formatted(.percent.precision(.fractionLength(2))),
                        second.settings.slippageRate.formatted(.percent.precision(.fractionLength(2)))
                    )
                }

                Section {
                    Text("review.compare_note")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("review.comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
    }

    private func comparisonHeader(_ record: BacktestRecord, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: String(localized: "review.test_format"), index))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(record.securityName)
                .font(.headline)
                .lineLimit(1)
            Text(record.strategyName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonRow(
        _ title: LocalizedStringKey,
        _ firstText: String,
        _ secondText: String,
        firstValue: Double? = nil,
        secondValue: Double? = nil,
        higherIsBetter: Bool? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                comparisonValue(firstText, isBetter: isBetter(firstValue, than: secondValue, higherIsBetter: higherIsBetter))
                comparisonValue(secondText, isBetter: isBetter(secondValue, than: firstValue, higherIsBetter: higherIsBetter))
            }
        }
        .padding(.vertical, 3)
    }

    private func comparisonValue(_ text: String, isBetter: Bool) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.body.monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            if isBetter {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityLabel(Text("review.better_result"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isBetter(_ value: Double?, than otherValue: Double?, higherIsBetter: Bool?) -> Bool {
        guard let value, let otherValue, let higherIsBetter, value != otherValue else { return false }
        return higherIsBetter ? value > otherValue : value < otherValue
    }

    private func period(for record: BacktestRecord) -> String {
        guard let start = record.settings.startDate,
              let end = record.settings.endDate
        else { return String(localized: "settings.full_period") }
        return "\(start.formatted(date: .numeric, time: .omitted))\n\(end.formatted(date: .numeric, time: .omitted))"
    }

    private func percent(_ value: Double?) -> String {
        value?.formatted(.percent.precision(.fractionLength(1))) ?? "—"
    }

    private func number(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(2))) ?? "—"
    }
}
