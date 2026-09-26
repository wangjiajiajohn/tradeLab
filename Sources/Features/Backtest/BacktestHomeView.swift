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
        Section("result.summary") {
            LabeledContent("result.return") {
                Text(result.cumulativeReturn, format: .percent.precision(.fractionLength(1)))
                    .foregroundStyle(result.cumulativeReturn >= 0 ? .green : .red)
                    .fontWeight(.semibold)
            }
            LabeledContent("result.drawdown") {
                Text(-result.maxDrawdown, format: .percent.precision(.fractionLength(1)))
            }
            LabeledContent("result.excess") {
                Text(result.excessReturn, format: .percent.precision(.fractionLength(1)))
                    .foregroundStyle(result.excessReturn >= 0 ? .green : .red)
            }
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
                    .symbolSize(58)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
            .frame(height: 240)
            Text("demo.synthetic_disclosure")
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
    }
}
