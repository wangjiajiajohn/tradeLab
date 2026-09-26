import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.data") {
                    NavigationLink {
                        MarketDataSettingsView()
                    } label: {
                        LabeledContent("settings.market_data_provider", value: marketDataStatus)
                    }
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        LabeledContent("settings.ai_provider", value: aiStatus)
                    }
                }

                Section("settings.appearance") {
                    Picker("settings.language", selection: $model.language) {
                        ForEach(AppModel.AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    Picker("settings.theme", selection: $model.appearance) {
                        Text("theme.system").tag(AppModel.Appearance.system)
                        Text("theme.light").tag(AppModel.Appearance.light)
                        Text("theme.dark").tag(AppModel.Appearance.dark)
                    }
                }

                Section("settings.privacy") {
                    LabeledContent(
                        "settings.network_first_run",
                        value: AppLocalization.string("status.disabled", locale: locale)
                    )
                    LabeledContent(
                        "settings.storage",
                        value: AppLocalization.string("settings.on_device", locale: locale)
                    )
                }

                Section {
                    Button("settings.reset_onboarding", role: .destructive) {
                        model.resetFirstRunExperience()
                    }
                } footer: {
                    Text("settings.research_disclaimer")
                }
            }
            .navigationTitle(model.language.localized("tab.settings"))
        }
    }

    private var marketDataStatus: String {
        switch model.marketDataSource {
        case .offline: AppLocalization.string("provider.offline", locale: locale)
        case .longbridge:
            model.hasLongbridgeCredentials
                ? AppLocalization.string("provider.longbridge", locale: locale)
                : AppLocalization.string("status.needs_configuration", locale: locale)
        }
    }

    private var aiStatus: String {
        switch model.aiProvider {
        case .disabled: AppLocalization.string("status.disabled", locale: locale)
        case .openAI:
            model.hasAIAPIKey ? "OpenAI" : AppLocalization.string("status.needs_configuration", locale: locale)
        case .deepSeek:
            model.hasAIAPIKey ? "DeepSeek" : AppLocalization.string("status.needs_configuration", locale: locale)
        }
    }
}

struct MarketDataSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var appKey = ""
    @State private var appSecret = ""
    @State private var accessToken = ""
    @State private var errorMessage: String?
    @State private var didSave = false

    private var canSave: Bool {
        model.marketDataSource == .offline
            || !appKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !appSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                Picker("settings.market_data_provider", selection: $model.marketDataSource) {
                    Text("provider.offline").tag(MarketDataSource.offline)
                    Text("provider.longbridge").tag(MarketDataSource.longbridge)
                }
            } footer: {
                Text(LocalizedStringKey(
                    model.marketDataSource == .offline
                        ? "provider.offline.description"
                        : "provider.longbridge.description"
                ))
            }

            if model.marketDataSource == .longbridge {
                Section("provider.credentials") {
                    TextField("provider.longbridge.app_key", text: $appKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecretEntryField(title: "provider.longbridge.app_secret", text: $appSecret)
                    SecretEntryField(title: "provider.longbridge.access_token", text: $accessToken)
                }
                Section {
                    Label("provider.keychain_note", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.hasLongbridgeCredentials {
                    Section {
                        Button("provider.remove_credentials", role: .destructive) { removeCredentials() }
                    }
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Label(
                        LocalizedStringKey(didSave ? "status.saved" : "action.save"),
                        systemImage: didSave ? "checkmark" : "square.and.arrow.down"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .navigationTitle("settings.market_data_provider")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadCredentials)
        .alert("error.title", isPresented: errorPresented) {
            Button("action.ok", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadCredentials() {
        appKey = CredentialStore.value(for: .longbridgeAppKey) ?? ""
        appSecret = CredentialStore.value(for: .longbridgeAppSecret) ?? ""
        accessToken = CredentialStore.value(for: .longbridgeAccessToken) ?? ""
    }

    private func save() {
        do {
            if model.marketDataSource == .longbridge {
                try CredentialStore.set(appKey, for: .longbridgeAppKey)
                try CredentialStore.set(appSecret, for: .longbridgeAppSecret)
                try CredentialStore.set(accessToken, for: .longbridgeAccessToken)
            }
            model.refreshCredentialStatus()
            didSave = true
        } catch {
            errorMessage = (error as? CredentialStoreError)?.localizedDescription(locale: model.language.locale)
                ?? error.localizedDescription
        }
    }

    private func removeCredentials() {
        do {
            try CredentialStore.remove(.longbridgeAppKey)
            try CredentialStore.remove(.longbridgeAppSecret)
            try CredentialStore.remove(.longbridgeAccessToken)
            appKey = ""
            appSecret = ""
            accessToken = ""
            model.marketDataSource = .offline
            model.refreshCredentialStatus()
            didSave = false
        } catch {
            errorMessage = (error as? CredentialStoreError)?.localizedDescription(locale: model.language.locale)
                ?? error.localizedDescription
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct AISettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apiKey = ""
    @State private var errorMessage: String?
    @State private var didSave = false

    private var canSave: Bool {
        model.aiProvider == .disabled
            || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !model.aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                Picker("settings.ai_provider", selection: $model.aiProvider) {
                    Text("provider.ai.disabled").tag(AIProvider.disabled)
                    Text("OpenAI").tag(AIProvider.openAI)
                    Text("DeepSeek").tag(AIProvider.deepSeek)
                }
            } footer: {
                Text("provider.ai.description")
            }

            if model.aiProvider != .disabled {
                Section("provider.credentials") {
                    SecretEntryField(title: "provider.ai.api_key", text: $apiKey)
                    TextField("provider.ai.model", text: $model.aiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Label("provider.keychain_note", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.hasAIAPIKey {
                    Section {
                        Button("provider.remove_credentials", role: .destructive) { removeCredential() }
                    }
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Label(
                        LocalizedStringKey(didSave ? "status.saved" : "action.save"),
                        systemImage: didSave ? "checkmark" : "square.and.arrow.down"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .navigationTitle("settings.ai_provider")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { apiKey = CredentialStore.value(for: .aiAPIKey) ?? "" }
        .onChange(of: model.aiProvider) { _, provider in
            if provider == .deepSeek, model.aiModel == "gpt-4.1-mini" { model.aiModel = "deepseek-chat" }
            if provider == .openAI, model.aiModel == "deepseek-chat" { model.aiModel = "gpt-4.1-mini" }
            didSave = false
        }
        .alert("error.title", isPresented: errorPresented) {
            Button("action.ok", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        do {
            if model.aiProvider != .disabled {
                try CredentialStore.set(apiKey, for: .aiAPIKey)
            }
            model.refreshCredentialStatus()
            didSave = true
        } catch {
            errorMessage = (error as? CredentialStoreError)?.localizedDescription(locale: model.language.locale)
                ?? error.localizedDescription
        }
    }

    private func removeCredential() {
        do {
            try CredentialStore.remove(.aiAPIKey)
            apiKey = ""
            model.aiProvider = .disabled
            model.refreshCredentialStatus()
            didSave = false
        } catch {
            errorMessage = (error as? CredentialStoreError)?.localizedDescription(locale: model.language.locale)
                ?? error.localizedDescription
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct SecretEntryField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    @State private var revealsText = false

    var body: some View {
        HStack {
            Group {
                if revealsText {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                revealsText.toggle()
            } label: {
                Image(systemName: revealsText ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey(
                revealsText ? "provider.hide_secret" : "provider.show_secret"
            )))
        }
    }
}
