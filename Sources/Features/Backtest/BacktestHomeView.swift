import Charts
import SwiftUI

struct BacktestHomeView: View {
    private enum ConfigurationSheet: String, Identifiable {
        case stock
        case strategy
        case settings

        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @State private var configurationSheet: ConfigurationSheet?

    var body: some View {
        NavigationStack {
            List {
                if let result = model.result {
                    ResultSections(
                        result: result,
                        changeStock: { configurationSheet = .stock },
                        changeStrategy: { configurationSheet = .strategy },
                        changeSettings: { configurationSheet = .settings },
                        runAgain: { Task { _ = await model.runBacktest() } }
                    )
                } else {
                    workflowSection
                    Section {
                        ContentUnavailableView(
                            "backtest.empty.title",
                            systemImage: "chart.xyaxis.line",
                            description: Text("backtest.empty.description")
                        )
                    }
                }
            }
            .navigationTitle("tab.backtest")
            .sheet(item: $configurationSheet) { sheet in
                switch sheet {
                case .stock: StockPickerView()
                case .strategy: StrategyPickerView()
                case .settings: BacktestSettingsSheet()
                }
            }
            .alert("error.title", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("action.ok", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var workflowSection: some View {
        Section("backtest.workflow") {
            Button { configurationSheet = .stock } label: {
                ConfigurationRow(
                    title: "backtest.stock",
                    value: model.selectedSecurity?.name ?? String(localized: "status.not_selected"),
                    symbol: "chart.line.uptrend.xyaxis"
                )
            }
            Button { configurationSheet = .strategy } label: {
                ConfigurationRow(
                    title: "backtest.strategy",
                    value: model.selectedStrategy?.name ?? String(localized: "status.not_selected"),
                    symbol: "slider.horizontal.3"
                )
            }
            Button { configurationSheet = .settings } label: {
                ConfigurationRow(
                    title: "backtest.conditions",
                    value: model.hasConfirmedSettings ? String(localized: "status.confirmed") : String(localized: "status.not_confirmed"),
                    symbol: "calendar.badge.clock"
                )
            }
            Button {
                Task { _ = await model.runBacktest() }
            } label: {
                HStack {
                    if model.isRunningBacktest { ProgressView().controlSize(.small) }
                    Label("backtest.run", systemImage: "play.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canRunBacktest || model.isRunningBacktest)
        }
    }
}

private struct ResultSections: View {
    let result: BacktestResult
    let changeStock: () -> Void
    let changeStrategy: () -> Void
    let changeSettings: () -> Void
    let runAgain: () -> Void

    var body: some View {
        Section {
            ResultOverview(result: result)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }

        Section("result.next_test") {
            Button(action: changeStock) {
                Label("result.change_stock", systemImage: "chart.line.uptrend.xyaxis")
            }
            Button(action: changeStrategy) {
                Label("result.change_strategy", systemImage: "slider.horizontal.3")
            }
            Button(action: changeSettings) {
                Label("result.change_settings", systemImage: "calendar.badge.clock")
            }
            Button(action: runAgain) {
                Label("result.run_again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }

        Section("result.price_signals") {
            Chart {
                ForEach(result.candles) { candle in
                    LineMark(
                        x: .value("Date", candle.date),
                        y: .value("Close", candle.close)
                    )
                    .foregroundStyle(.tint)
                }
                ForEach(result.trades) { trade in
                    PointMark(
                        x: .value("Date", trade.date),
                        y: .value("Price", trade.price)
                    )
                    .foregroundStyle(trade.side == .buy ? .green : .red)
                    .symbol(trade.side == .buy ? .triangle : .circle)
                    .symbolSize(trade.side == .buy ? 32 : 64)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
            .frame(height: 240)
            Text(
                LocalizedStringKey(
                    result.security.isSyntheticDemo
                        ? "demo.synthetic_disclosure"
                        : "demo.development_disclosure"
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("result.equity") {
            Chart {
                ForEach(result.equityCurve) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Strategy", point.strategyValue))
                        .foregroundStyle(by: .value("Series", String(localized: "result.strategy_value")))
                }
                ForEach(result.equityCurve) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Benchmark", point.benchmarkValue))
                        .foregroundStyle(by: .value("Series", String(localized: "result.benchmark")))
                }
            }
            .chartForegroundStyleScale([
                String(localized: "result.strategy_value"): Color.accentColor,
                String(localized: "result.benchmark"): Color.secondary
            ])
            .frame(height: 220)
        }

        Section("result.trades") {
            LabeledContent("result.trade_count", value: "\(result.trades.count)")
            ForEach(result.trades.prefix(6)) { trade in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(trade.side == .buy ? "trade.buy" : "trade.sell")
                            .foregroundStyle(trade.side == .buy ? .green : .red)
                        Spacer()
                        Text(trade.price, format: .currency(code: result.security.currency))
                    }
                    Text(trade.date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("result.interpretation") {
            Label {
                Text(benchmarkSummary)
            } icon: {
                Image(systemName: result.excessReturn >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(result.excessReturn >= 0 ? .green : .orange)
            }
            Label("result.reliability_note", systemImage: "checkmark.shield")
                .foregroundStyle(.secondary)
        }
    }

    private var benchmarkSummary: String {
        let value = abs(result.excessReturn).formatted(.percent.precision(.fractionLength(1)))
        let key = result.excessReturn >= 0
            ? "result.benchmark_outperformed_format"
            : "result.benchmark_underperformed_format"
        return String(format: String(localized: String.LocalizationValue(key)), value)
    }
}

private struct ResultOverview: View {
    let result: BacktestResult

    private var resultColor: Color { result.netProfit >= 0 ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(result.security.name) · \(result.strategy.name)")
                    .font(.headline)
                if let first = result.candles.first?.date,
                   let last = result.candles.last?.date {
                    Text("\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("result.final_value")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(result.finalValue, format: .currency(code: result.security.currency))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.75)
                HStack(spacing: 6) {
                    Image(systemName: result.netProfit >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(result.netProfit, format: .currency(code: result.security.currency))
                    Text(result.cumulativeReturn, format: .percent.precision(.fractionLength(1)))
                }
                .font(.headline)
                .foregroundStyle(resultColor)
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    ResultMetric(
                        title: "result.total_bought",
                        value: result.totalBuyCost.formatted(.currency(code: result.security.currency)),
                        symbol: "calendar.badge.plus"
                    )
                    ResultMetric(
                        title: "result.drawdown",
                        value: (-result.maxDrawdown).formatted(.percent.precision(.fractionLength(1))),
                        symbol: "arrow.down.right",
                        tint: .orange
                    )
                }
                GridRow {
                    ResultMetric(
                        title: "result.excess",
                        value: result.excessReturn.formatted(.percent.precision(.fractionLength(1))),
                        symbol: "chart.line.uptrend.xyaxis",
                        tint: result.excessReturn >= 0 ? .green : .orange
                    )
                    ResultMetric(
                        title: "result.trade_count",
                        value: "\(result.trades.count)",
                        symbol: "list.number"
                    )
                }
                GridRow {
                    ResultMetric(
                        title: "result.annualized_return",
                        value: result.annualizedReturn.formatted(.percent.precision(.fractionLength(1))),
                        symbol: "calendar.badge.clock",
                        tint: result.annualizedReturn >= 0 ? .green : .red
                    )
                    ResultMetric(
                        title: "result.volatility",
                        value: result.annualizedVolatility.formatted(.percent.precision(.fractionLength(1))),
                        symbol: "waveform.path.ecg",
                        tint: .orange
                    )
                }
                GridRow {
                    ResultMetric(
                        title: "result.sharpe",
                        value: result.sharpeRatio?.formatted(.number.precision(.fractionLength(2))) ?? "—",
                        symbol: "scale.3d"
                    )
                    ResultMetric(
                        title: "result.total_fees",
                        value: result.totalFees.formatted(.currency(code: result.security.currency)),
                        symbol: "banknote"
                    )
                }
            }
        }
        .padding(20)
        .background(.background, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.separator.opacity(0.35), lineWidth: 0.5)
        }
    }
}

private struct ResultMetric: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

private struct ConfigurationRow: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }
}

private struct StockPickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.securities) { security in
                Button {
                    model.selectSecurity(security)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(security.name).font(.headline)
                            Text("\(security.symbol) · \(marketName(security.market))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.selectedSecurityID == security.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("result.change_stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
    }

    private func marketName(_ market: Market) -> String {
        switch market {
        case .hk: String(localized: "market.hk")
        case .us: String(localized: "market.us")
        default: market.rawValue.uppercased()
        }
    }
}

private struct StrategyPickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.strategies) { strategy in
                Button {
                    model.selectStrategy(strategy)
                    dismiss()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(strategy.name).font(.headline)
                            Text(strategy.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.selectedStrategyID == strategy.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
            .navigationTitle("result.change_strategy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
    }
}

private struct BacktestSettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BacktestSettings.demo

    var body: some View {
        NavigationStack {
            Form {
                if let availableRange {
                    Section("settings.period") {
                        DatePicker(
                            "settings.start_date",
                            selection: startDateBinding,
                            in: availableRange.lowerBound...effectiveEndDate,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "settings.end_date",
                            selection: endDateBinding,
                            in: effectiveStartDate...availableRange.upperBound,
                            displayedComponents: .date
                        )
                    }
                }
                Section("settings.capital") {
                    TextField("settings.capital", value: $draft.initialCapital, format: .number)
                        .keyboardType(.decimalPad)
                }
                Section("settings.costs") {
                    LabeledContent("settings.commission") {
                        Text(draft.commissionRate, format: .percent.precision(.fractionLength(2)))
                    }
                    Slider(value: $draft.commissionRate, in: 0...0.01, step: 0.0005)
                    LabeledContent("settings.slippage") {
                        Text(draft.slippageRate, format: .percent.precision(.fractionLength(2)))
                    }
                    Slider(value: $draft.slippageRate, in: 0...0.01, step: 0.0005)
                }
            }
            .navigationTitle("backtest.conditions")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                draft = model.settings
                clampDraftPeriod()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") {
                        model.updateSettings(draft)
                        model.hasConfirmedSettings = true
                        dismiss()
                    }
                    .disabled(draft.initialCapital <= 0)
                }
            }
        }
    }

    private var availableRange: ClosedRange<Date>? {
        guard let first = model.selectedCandles.first?.date,
              let last = model.selectedCandles.last?.date
        else { return nil }
        return first...last
    }

    private var startDateBinding: Binding<Date> {
        Binding(
            get: { effectiveStartDate },
            set: { draft.startDate = min($0, effectiveEndDate) }
        )
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { effectiveEndDate },
            set: { draft.endDate = max($0, effectiveStartDate) }
        )
    }

    private var effectiveStartDate: Date {
        guard let availableRange else { return .now }
        return min(
            max(draft.startDate ?? availableRange.lowerBound, availableRange.lowerBound),
            availableRange.upperBound
        )
    }

    private var effectiveEndDate: Date {
        guard let availableRange else { return .now }
        return min(
            max(draft.endDate ?? availableRange.upperBound, effectiveStartDate),
            availableRange.upperBound
        )
    }

    private func clampDraftPeriod() {
        guard availableRange != nil else { return }
        draft.startDate = effectiveStartDate
        draft.endDate = effectiveEndDate
    }
}
