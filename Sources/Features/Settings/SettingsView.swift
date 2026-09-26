import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.data") {
                    LabeledContent("settings.demo_data", value: String(localized: "status.ready"))
                    LabeledContent("settings.online_provider", value: String(localized: "status.not_configured"))
                }

                Section("settings.appearance") {
                    Picker("settings.theme", selection: $model.appearance) {
                        Text("theme.system").tag(AppModel.Appearance.system)
                        Text("theme.light").tag(AppModel.Appearance.light)
                        Text("theme.dark").tag(AppModel.Appearance.dark)
                    }
                }

                Section("settings.privacy") {
                    LabeledContent("settings.network_first_run", value: String(localized: "status.disabled"))
                    LabeledContent("settings.storage", value: String(localized: "settings.on_device"))
                }

                Section {
                    Button("settings.reset_onboarding", role: .destructive) {
                        model.resetFirstRunExperience()
                    }
                } footer: {
                    Text("settings.research_disclaimer")
                }
            }
            .navigationTitle("tab.settings")
        }
    }
}
