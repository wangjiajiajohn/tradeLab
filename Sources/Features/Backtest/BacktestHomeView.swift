import Charts
import SwiftUI

struct BacktestHomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("backtest.workflow") {
                    LabeledContent("backtest.stock", value: model.selectedSecurity?.name ?? String(localized: "status.not_selected"))
                    LabeledContent("backtest.strategy", value: model.selectedStrategy?.name ?? String(localized: "status.not_selected"))
                    LabeledContent("backtest.conditions", value: model.hasConfirmedSettings ? String(localized: "status.confirmed") : String(localized: "status.not_confirmed"))
                    Button {
                        _ = model.runBacktest()
                    } label: {
                        Label("backtest.run", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canRunBacktest)
                }

                if let result = model.result {
                    ResultSections(result: result)
                } else {
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
        }
    }
}

private struct ResultSections: View {
    let result: BacktestResult

    var body: some View {
        Section {
            ResultOverview(result: result)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
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
