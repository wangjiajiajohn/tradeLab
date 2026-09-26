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

    func pullDownResearchDisclosure(belowNavigationBar: Bool = true) -> some View {
        modifier(PullDownResearchDisclosureModifier(belowNavigationBar: belowNavigationBar))
    }
}

private struct PullDownResearchDisclosureModifier: ViewModifier {
    @Environment(\.locale) private var locale
    let belowNavigationBar: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ScrollDisclosureInstaller(
                    text: AppLocalization.string("disclosure.pull_down", locale: locale),
                    belowNavigationBar: belowNavigationBar
                )
                    .frame(width: 0, height: 0)
            }
    }
}

private struct ScrollDisclosureInstaller: UIViewRepresentable {
    let text: String
    let belowNavigationBar: Bool

    func makeUIView(context: Context) -> ScrollDisclosureInstallerView {
        let view = ScrollDisclosureInstallerView()
        view.text = text
        view.belowNavigationBar = belowNavigationBar
        return view
    }

    func updateUIView(_ uiView: ScrollDisclosureInstallerView, context: Context) {
        uiView.text = text
        uiView.belowNavigationBar = belowNavigationBar
        uiView.attachIfNeeded()
    }

    static func dismantleUIView(_ uiView: ScrollDisclosureInstallerView, coordinator: ()) {
        uiView.detach()
    }
}

private final class ScrollDisclosureInstallerView: UIView {
    var text = "" {
        didSet { disclosureLabel.text = text }
    }

    private weak var observedScrollView: UIScrollView?
    var belowNavigationBar = true
    private let disclosureHeight: CGFloat = 36
    private lazy var disclosureLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.isAccessibilityElement = false
        label.autoresizingMask = [.flexibleWidth]
        return label
    }()

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
        disclosureLabel.text = text
        disclosureLabel.frame = CGRect(
            x: 16,
            y: belowNavigationBar
                ? -disclosureHeight
                : -scrollView.adjustedContentInset.top - disclosureHeight,
            width: max(0, scrollView.bounds.width - 32),
            height: disclosureHeight
        )
        scrollView.addSubview(disclosureLabel)
    }

    func detach() {
        disclosureLabel.removeFromSuperview()
        observedScrollView = nil
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
