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
    @Environment(\.locale) private var locale
    @State private var configurationSheet: ConfigurationSheet?

    var body: some View {
        NavigationStack {
            List {
                configurationSection

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
            .navigationTitle(model.language.localized("tab.backtest"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard !model.isRunningBacktest else { return }
                        Task { _ = await model.runBacktest() }
                    } label: {
                        if model.isRunningBacktest {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("backtest.run", systemImage: "play.fill")
                        }
                    }
                    .disabled(!model.canRunBacktest)
                    .allowsHitTesting(!model.isRunningBacktest)
                    .accessibilityLabel(model.language.localized(
                        model.isRunningBacktest ? "backtest.running" : "backtest.run"
                    ))
                }
            }
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

    private var configurationSection: some View {
        Section("backtest.workflow") {
            Button { configurationSheet = .stock } label: {
                ConfigurationRow(
                    title: "backtest.stock",
                    value: model.selectedSecurity?.name
                        ?? AppLocalization.string("status.not_selected", locale: locale),
                    symbol: "chart.line.uptrend.xyaxis"
                )
            }
            Button { configurationSheet = .strategy } label: {
                ConfigurationRow(
                    title: "backtest.strategy",
                    value: model.selectedStrategy?.name
                        ?? AppLocalization.string("status.not_selected", locale: locale),
                    symbol: "slider.horizontal.3"
                )
            }
            Button { configurationSheet = .settings } label: {
                ConfigurationRow(
                    title: "backtest.conditions",
                    value: model.hasConfirmedSettings
                        ? AppLocalization.string("status.confirmed", locale: locale)
                        : AppLocalization.string("status.not_confirmed", locale: locale),
                    symbol: "calendar.badge.clock"
                )
            }
        }
    }
}

private struct ResultSections: View {
    let result: BacktestResult
    @Environment(\.locale) private var locale

    var body: some View {
        let report = BacktestDiagnostics.report(result)

        Section {
            ResultOverview(result: result)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }

        Section {
            CurveProfileView(profile: report.curve)
        } header: {
            Text("result.curve_profile")
        }

        Section {
            ForEach(report.diagnostics) { diagnostic in
                StrategyDiagnosticRow(diagnostic: diagnostic)
            }
        } header: {
            Text("result.diagnostics")
        }

        if !report.operationFindings.isEmpty {
            Section {
                ForEach(report.operationFindings) { finding in
                    OperationFindingRow(finding: finding)
                }
            } header: {
                Text("result.operation_review")
            } footer: {
                Text("result.operation_hindsight")
            }
        }

        Section {
            ForEach(report.optimizations) { optimization in
                OptimizationRow(optimization: optimization)
            }
        } header: {
            Text("result.optimizations")
        } footer: {
            Text("result.diagnostics_scope")
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
                        .foregroundStyle(by: .value(
                            "Series",
                            AppLocalization.string("result.strategy_value", locale: locale)
                        ))
                }
                ForEach(result.equityCurve) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Benchmark", point.benchmarkValue))
                        .foregroundStyle(by: .value(
                            "Series",
                            AppLocalization.string("result.benchmark", locale: locale)
                        ))
                }
            }
            .chartForegroundStyleScale([
                AppLocalization.string("result.strategy_value", locale: locale): Color.accentColor,
                AppLocalization.string("result.benchmark", locale: locale): Color.secondary
            ])
            .frame(height: 220)
        }

        Section("result.trades") {
            NavigationLink {
                BacktestOrdersView(
                    trades: result.trades,
                    currencyCode: result.security.currency
                )
            } label: {
                LabeledContent("result.view_all_orders", value: "\(result.trades.count)")
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
        return String(
            format: AppLocalization.string(key, locale: locale),
            value
        )
    }

}

private struct CurveProfileView: View {
    let profile: BacktestCurveProfile
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(trendTitle)
                        .font(.headline)
                    Text(trendDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: trendIcon)
                    .foregroundStyle(trendColor)
            }

            Divider()

            LabeledContent("result.curve.volatility", value: percent(profile.annualizedVolatility))

            if let peak = profile.drawdownPeak, let trough = profile.drawdownTrough {
                VStack(alignment: .leading, spacing: 3) {
                    LabeledContent("result.curve.max_drawdown", value: percent(profile.maximumDrawdown))
                    Text(String(
                        format: localized("result.curve.drawdown_period_format"),
                        date(peak),
                        date(trough)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var trendTitle: String {
        localized("result.curve.\(trendKey).title")
    }

    private var trendDetail: String {
        String(
            format: localized("result.curve.\(trendKey).\(pathKey)_format"),
            percent(abs(profile.returnRate))
        )
    }

    private var trendKey: String {
        switch profile.trend {
        case .rising: "rising"
        case .falling: "falling"
        case .sideways: "sideways"
        }
    }

    private var pathKey: String {
        if profile.efficiency < 0.20 { return "choppy" }
        if profile.efficiency > 0.45 { return "directional" }
        return "mixed"
    }

    private var trendIcon: String {
        switch profile.trend {
        case .rising: "chart.line.uptrend.xyaxis"
        case .falling: "chart.line.downtrend.xyaxis"
        case .sideways: "arrow.left.and.right"
        }
    }

    private var trendColor: Color {
        switch profile.trend {
        case .rising: .green
        case .falling: .red
        case .sideways: .orange
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: locale)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)).locale(locale))
    }

    private func date(_ value: Date) -> String {
        value.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
    }
}

private struct StrategyDiagnosticRow: View {
    let diagnostic: BacktestDiagnostic
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch diagnostic.severity {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .information: "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch diagnostic.severity {
        case .critical: .red
        case .warning: .orange
        case .information: .blue
        }
    }

    private var title: String {
        localized("result.diagnostic.\(key).title")
    }

    private var detail: String {
        switch diagnostic.kind {
        case let .risingMarketDCA(gap), let .underperformed(gap):
            return formattedDetail(percent(gap))
        case let .noDownsideProtection(drawdown), let .deepDrawdown(drawdown):
            return formattedDetail(percent(drawdown))
        case let .tooFewSignals(entries):
            return formattedDetail(entries)
        case let .whipsaw(losses, closedTrades):
            return formattedDetail(closedTrades, losses)
        case let .missedTrend(exposure), let .highCosts(exposure):
            return formattedDetail(percent(exposure))
        case let .shortSample(days):
            return formattedDetail(days)
        case let .noClearEdge(gap):
            return formattedDetail(percent(abs(gap)))
        case .noObviousIssue:
            return localized("result.diagnostic.no_obvious_issue.detail")
        }
    }

    private var key: String {
        switch diagnostic.kind {
        case .risingMarketDCA: "dca_lag"
        case .underperformed: "underperformed"
        case .noDownsideProtection: "limited_protection"
        case .deepDrawdown: "deep_drawdown"
        case .tooFewSignals: "few_signals"
        case .whipsaw: "whipsaw"
        case .missedTrend: "missed_trend"
        case .highCosts: "high_costs"
        case .shortSample: "short_sample"
        case .noClearEdge: "no_clear_edge"
        case .noObviousIssue: "no_obvious_issue"
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: locale)
    }

    private func formattedDetail(_ arguments: CVarArg...) -> String {
        String(format: localized("result.diagnostic.\(key).detail"), arguments: arguments)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(
            .percent
                .precision(.fractionLength(1))
                .locale(locale)
        )
    }
}

private struct OperationFindingRow: View {
    let finding: BacktestOperationFinding
    @Environment(\.locale) private var locale

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        localized("result.operation.\(key).title")
    }

    private var detail: String {
        switch finding.kind {
        case let .buyBeforeDecline(date, decline, tradingDays):
            return String(format: localized("result.operation.buy_before_decline.detail"), formattedDate(date), tradingDays, percent(decline))
        case let .sellBeforeRise(date, rise, tradingDays):
            return String(format: localized("result.operation.sell_before_rise.detail"), formattedDate(date), tradingDays, percent(rise))
        case let .losingRoundTrip(entry, exit, loss):
            return String(format: localized("result.operation.losing_trade.detail"), formattedDate(entry), formattedDate(exit), percent(loss))
        }
    }

    private var key: String {
        switch finding.kind {
        case .buyBeforeDecline: "buy_before_decline"
        case .sellBeforeRise: "sell_before_rise"
        case .losingRoundTrip: "losing_trade"
        }
    }

    private var icon: String {
        switch finding.kind {
        case .buyBeforeDecline: "arrow.down.forward.circle.fill"
        case .sellBeforeRise: "arrow.up.forward.circle.fill"
        case .losingRoundTrip: "xmark.circle.fill"
        }
    }

    private var color: Color {
        finding.severity == .critical ? .red : .orange
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: locale)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)).locale(locale))
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
    }
}

private struct OptimizationRow: View {
    let optimization: BacktestOptimization
    @Environment(\.locale) private var locale

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("result.optimization.\(key).title"))
                    .font(.headline)
                Text(localized("result.optimization.\(key).detail"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }

    private var key: String {
        switch optimization.kind {
        case .compareFrontLoadedEntry: "front_load"
        case .addTrendConfirmation: "trend_confirmation"
        case .reduceTrendLag: "reduce_lag"
        case .confirmBreakout: "breakout_confirmation"
        case .addRiskExit: "risk_exit"
        case .extendSample: "extend_sample"
        case .crossValidate: "cross_validate"
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: locale)
    }
}

private struct BacktestOrdersView: View {
    let trades: [SimulatedTrade]
    let currencyCode: String
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            if trades.isEmpty {
                ContentUnavailableView(
                    "result.orders.empty",
                    systemImage: "list.bullet.rectangle"
                )
            } else {
                ForEach(trades) { trade in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(trade.side == .buy ? "trade.buy" : "trade.sell")
                                .font(.headline)
                                .foregroundStyle(trade.side == .buy ? .green : .red)
                            Spacer()
                            Text(trade.price, format: .currency(code: currencyCode))
                                .font(.headline)
                        }
                        HStack {
                            Text(trade.date.formatted(
                                Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
                            ))
                            Spacer()
                            Text("\(trade.quantity)")
                                .accessibilityLabel("\(trade.quantity) \(AppLocalization.string("trades.quantity", locale: locale))")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("result.all_orders")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ResultOverview: View {
    let result: BacktestResult
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale

    private var resultColor: Color { result.netProfit >= 0 ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(securityName) · \(strategyName)")
                    .font(.headline)
                if let first = result.candles.first?.date,
                   let last = result.candles.last?.date {
                    Text("\(formatted(first)) – \(formatted(last))")
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

            Divider()

            Label("result.hypothetical_disclosure", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(.background, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.separator.opacity(0.35), lineWidth: 0.5)
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
    }

    private var securityName: String {
        model.localizedSecurityName(id: result.security.id, fallback: result.security.name)
    }

    private var strategyName: String {
        model.localizedStrategyName(id: result.strategy.id, fallback: result.strategy.name)
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
    private enum MarketFilter: String, CaseIterable, Identifiable {
        case all
        case us
        case hk

        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var searchText = ""
    @State private var showingDataSourceSettings = false
    @State private var onlineSearchResults: [Security] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var completedSearchQuery = ""
    @State private var marketFilter: MarketFilter = .all

    var body: some View {
        NavigationStack {
            Group {
                if needsDataSourceSetup {
                    stockList
                } else {
                    stockList
                        .searchable(
                            text: $searchText,
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "stock.search.prompt"
                        )
                }
            }
            .navigationTitle("result.change_stock")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if (isSearching || isWaitingForSearchResponse) && filteredSecurities.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                } else if let searchError, filteredSecurities.isEmpty {
                    ContentUnavailableView {
                        Label("stock.search.failed", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(searchError)
                    }
                } else if !needsDataSourceSetup && filteredSecurities.isEmpty {
                    ContentUnavailableView {
                        Label("stock.search.no_results", systemImage: "magnifyingglass")
                    } description: {
                        Text("stock.search.no_results.description")
                    }
                }
            }
            .navigationDestination(isPresented: $showingDataSourceSettings) {
                MarketDataSettingsView(presentsProviderPickerOnAppear: true)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
            .task(id: searchText) {
                await performSearch(for: searchText)
            }
        }
    }

    @MainActor
    private func performSearch(for rawQuery: String) async {
        let query = normalizedQuery(rawQuery)
        onlineSearchResults = []
        searchError = nil

        guard !needsDataSourceSetup, !query.isEmpty else {
            isSearching = false
            completedSearchQuery = query
            return
        }

        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            try Task.checkCancellation()
            let results = try await model.searchSecurities(matching: query)
            try Task.checkCancellation()
            guard normalizedQuery(searchText) == query else { return }
            onlineSearchResults = results
            completedSearchQuery = query
            searchError = nil
            isSearching = false
        } catch {
            guard !Task.isCancelled, normalizedQuery(searchText) == query else { return }
            completedSearchQuery = query
            isSearching = false
            if let marketError = error as? OnlineMarketDataError {
                searchError = marketError.localizedDescription(locale: locale)
            } else {
                searchError = error.localizedDescription
            }
        }
    }

    private func normalizedQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var stockList: some View {
        List {
            Section {
                Picker("stock.filter.market", selection: $marketFilter) {
                    Text("stock.filter.all").tag(MarketFilter.all)
                    Text("market.us").tag(MarketFilter.us)
                    Text("market.hk").tag(MarketFilter.hk)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))

            if needsDataSourceSetup {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive.badge.wifi")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 44, height: 44)
                                .background(.orange.opacity(0.14), in: .rect(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("stock.search.configure.title")
                                    .font(.headline)
                                Text("stock.search.configure.description")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            showingDataSourceSettings = true
                        } label: {
                            Label("stock.search.configure.action", systemImage: "gearshape.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.large)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.orange.opacity(0.08))
            }

            ForEach(filteredSecurities) { security in
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
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .listSectionSpacing(12)
    }

    private var needsDataSourceSetup: Bool {
        model.marketDataSource == .offline || !model.hasSelectedMarketDataCredentials
    }

    private var filteredSecurities: [Security] {
        let query = normalizedQuery(searchText)
        let available = model.securities + model.discoveredSecurities
        let matches: [Security]
        if query.isEmpty {
            matches = available
        } else if needsDataSourceSetup {
            matches = available.filter { security in
                security.name.localizedStandardContains(query)
                    || security.symbol.localizedStandardContains(query)
                    || security.id.localizedStandardContains(query)
                    || marketName(security.market).localizedStandardContains(query)
            }
        } else if completedSearchQuery == query {
            matches = onlineSearchResults
        } else {
            matches = []
        }

        let unique = matches.reduce(into: [Security]()) { result, security in
            if !result.contains(where: { $0.id == security.id }) { result.append(security) }
        }
        return unique.filter { security in
            switch marketFilter {
            case .all: true
            case .us: security.market == .us
            case .hk: security.market == .hk
            }
        }
    }

    private var isWaitingForSearchResponse: Bool {
        let query = normalizedQuery(searchText)
        return !needsDataSourceSetup && !query.isEmpty && completedSearchQuery != query
    }

    private func marketName(_ market: Market) -> String {
        switch market {
        case .hk: AppLocalization.string("market.hk", locale: locale)
        case .us: AppLocalization.string("market.us", locale: locale)
        default: market.rawValue.uppercased()
        }
    }
}

private struct StrategyPickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var customStrategies: [TradingStrategy] {
        model.strategies.filter { !$0.isBuiltIn }
    }

    private var builtInStrategies: [TradingStrategy] {
        model.strategies.filter(\.isBuiltIn)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("strategies.custom") {
                    if customStrategies.isEmpty {
                        Label("strategies.custom.empty_prompt", systemImage: "plus.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(customStrategies) { strategy in
                            strategyRow(strategy)
                        }
                    }
                }

                Section("strategies.built_in") {
                    ForEach(builtInStrategies) { strategy in
                        strategyRow(strategy)
                    }
                }
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

    private func strategyRow(_ strategy: TradingStrategy) -> some View {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
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
        if let first = model.selectedCandles.first?.date,
           let last = model.selectedCandles.last?.date {
            return first...last
        }
        guard model.selectedSecurity != nil,
              model.marketDataSource != .offline
        else { return nil }
        return BacktestSettings.defaultPeriod()
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
