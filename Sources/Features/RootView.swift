import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.hasCompletedFirstBacktest {
                MainTabView()
                    .transition(.opacity)
            } else {
                FirstBacktestFlowView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.hasCompletedFirstBacktest)
    }
}

private struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            BacktestHomeView()
                .tabItem { Label("tab.backtest", systemImage: "chart.xyaxis.line") }
                .tag(AppModel.MainTab.backtest)

            StrategyListView()
                .tabItem { Label("tab.strategies", systemImage: "slider.horizontal.3") }
                .tag(AppModel.MainTab.strategies)

            ReviewView()
                .tabItem { Label("tab.review", systemImage: "book.pages") }
                .tag(AppModel.MainTab.review)

            SettingsView()
                .tabItem { Label("tab.settings", systemImage: "gearshape") }
                .tag(AppModel.MainTab.settings)
        }
    }
}
