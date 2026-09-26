import SwiftUI
import UIKit

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

    func pullDownResearchDisclosure() -> some View {
        modifier(PullDownResearchDisclosureModifier())
    }
}

private struct PullDownResearchDisclosureModifier: ViewModifier {
    @State private var pullDistance: CGFloat = 0

    private let disclosureHeight: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .background {
                ScrollPullObserver(distance: $pullDistance)
                    .frame(width: 0, height: 0)
            }
            .overlay(alignment: .top) {
                Label("disclosure.pull_down", systemImage: "info.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
                    .frame(height: disclosureHeight)
                    // Keep the disclosure immediately above the scroll content at
                    // rest. During overscroll it moves one-for-one with the list,
                    // just like a header that belongs to the scrolling page.
                    .offset(y: pullDistance - disclosureHeight)
                    .opacity(pullDistance > 0 ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(pullDistance < disclosureHeight * 0.8)
            }
    }
}

private struct ScrollPullObserver: UIViewRepresentable {
    @Binding var distance: CGFloat

    func makeUIView(context: Context) -> ScrollPullObserverView {
        let view = ScrollPullObserverView()
        view.onDistanceChange = { distance = $0 }
        return view
    }

    func updateUIView(_ uiView: ScrollPullObserverView, context: Context) {
        uiView.onDistanceChange = { distance = $0 }
        uiView.attachIfNeeded()
    }

    static func dismantleUIView(_ uiView: ScrollPullObserverView, coordinator: ()) {
        uiView.detach()
    }
}

private final class ScrollPullObserverView: UIView {
    var onDistanceChange: ((CGFloat) -> Void)?
    private weak var observedScrollView: UIScrollView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            detach()
        } else {
            DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
        }
    }

    func attachIfNeeded() {
        guard observedScrollView == nil, let scrollView = nearestVerticalScrollView() else { return }
        observedScrollView = scrollView
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan))
    }

    func detach() {
        observedScrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan))
        observedScrollView = nil
        onDistanceChange?(0)
    }

    @objc private func handlePan() {
        guard let scrollView = observedScrollView else { return }
        let distance = max(0, -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
        onDistanceChange?(distance)
    }

    private func nearestVerticalScrollView() -> UIScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView { return scrollView }
            if let scrollView = verticalScrollView(in: view) { return scrollView }
            ancestor = view.superview
        }
        return nil
    }

    private func verticalScrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews where subview !== self {
            if let scrollView = subview as? UIScrollView,
               scrollView.alwaysBounceVertical || scrollView.contentSize.height > scrollView.bounds.height {
                return scrollView
            }
            if let match = verticalScrollView(in: subview) { return match }
        }
        return nil
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
