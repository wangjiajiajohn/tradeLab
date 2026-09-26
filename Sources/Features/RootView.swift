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
        .id(model.language.rawValue)
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

extension View {
    func tabToolbarJellyEffect() -> some View {
        modifier(TabToolbarJellyModifier())
    }

}

private struct TabToolbarJellyModifier: ViewModifier {
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: isPressed ? 1.04 : 1, y: isPressed ? 0.9 : 1)
            .animation(
                .interactiveSpring(response: 0.22, dampingFraction: 0.58, blendDuration: 0.08),
                value: isPressed
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
            )
    }
}
