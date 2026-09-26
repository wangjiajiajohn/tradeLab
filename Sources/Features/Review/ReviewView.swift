import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.backtestHistory.isEmpty {
                    ContentUnavailableView(
                        "review.empty.title",
                        systemImage: "book.pages",
                        description: Text("review.empty.description")
                    )
                } else {
                    List(model.backtestHistory) { record in
                        NavigationLink {
                            BacktestRecordDetail(record: record)
                        } label: {
                            BacktestRecordRow(record: record)
                        }
                    }
                }
            }
            .navigationTitle("tab.review")
        }
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
                LabeledContent("result.trade_count", value: "\(record.tradeCount)")
            }

            Section("review.assumptions") {
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
            } footer: {
                Text("review.restore_hint")
            }
        }
        .navigationTitle("review.detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
