import SwiftUI

@main
struct TradeLabV2App: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.locale, model.language.locale)
                .preferredColorScheme(model.appearance.colorScheme)
        }
    }
}
