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
        case .claude:
            model.hasAIAPIKey ? "Claude" : AppLocalization.string("status.needs_configuration", locale: locale)
        case .gemini:
            model.hasAIAPIKey ? "Gemini" : AppLocalization.string("status.needs_configuration", locale: locale)
        case .kimi:
            model.hasAIAPIKey ? "Kimi" : AppLocalization.string("status.needs_configuration", locale: locale)
        }
    }
}

struct MarketDataSettingsView: View {
    let presentsProviderPickerOnAppear: Bool
    @EnvironmentObject private var model: AppModel
    @State private var appKey = ""
    @State private var appSecret = ""
    @State private var accessToken = ""
    @State private var errorMessage: String?
    @State private var didSave = false
    @State private var showingProviderPicker = false
    @State private var hasPresentedProviderPicker = false

    init(presentsProviderPickerOnAppear: Bool = false) {
        self.presentsProviderPickerOnAppear = presentsProviderPickerOnAppear
    }

    private var canSave: Bool {
        !appKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("settings.market_data_provider")
                    Spacer()
                    Button {
                        showingProviderPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(providerName(model.marketDataSource))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingProviderPicker, arrowEdge: .top) {
                        providerPickerMenu
                            .presentationCompactAdaptation(.popover)
                    }
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

        }
        .navigationTitle("settings.market_data_provider")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.marketDataSource == .longbridge {
                Button {
                    save()
                } label: {
                    Label(
                        LocalizedStringKey(didSave ? "status.saved" : "action.save"),
                        systemImage: didSave ? "checkmark" : "square.and.arrow.down"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .onAppear {
            loadCredentials()
            guard presentsProviderPickerOnAppear, !hasPresentedProviderPicker else { return }
            hasPresentedProviderPicker = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingProviderPicker = true
            }
        }
        .onChange(of: appKey) { _, _ in didSave = false }
        .onChange(of: appSecret) { _, _ in didSave = false }
        .onChange(of: accessToken) { _, _ in didSave = false }
        .alert("error.title", isPresented: errorPresented) {
            Button("action.ok", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var providerPickerMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            providerButton(.offline)
            Divider()
            providerButton(.longbridge)
        }
        .padding(.vertical, 6)
        .frame(minWidth: 220)
    }

    private func providerButton(_ source: MarketDataSource) -> some View {
        Button {
            model.marketDataSource = source
            showingProviderPicker = false
        } label: {
            HStack(spacing: 12) {
                Text(providerName(source))
                    .foregroundStyle(.primary)
                Spacer(minLength: 20)
                if model.marketDataSource == source {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func providerName(_ source: MarketDataSource) -> LocalizedStringKey {
        switch source {
        case .offline: "provider.offline"
        case .longbridge: "provider.longbridge"
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
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                Picker("settings.ai_provider", selection: $model.aiProvider) {
                    Text("provider.ai.disabled").tag(AIProvider.disabled)
                    Text("OpenAI").tag(AIProvider.openAI)
                    Text("DeepSeek").tag(AIProvider.deepSeek)
                    Text("Claude").tag(AIProvider.claude)
                    Text("Gemini").tag(AIProvider.gemini)
                    Text("Kimi").tag(AIProvider.kimi)
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

        }
        .navigationTitle("settings.ai_provider")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.aiProvider != .disabled {
                Button {
                    save()
                } label: {
                    Label(
                        LocalizedStringKey(didSave ? "status.saved" : "action.save"),
                        systemImage: didSave ? "checkmark" : "square.and.arrow.down"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .onAppear { loadConfiguration(for: model.aiProvider) }
        .onChange(of: model.aiProvider) { _, provider in
            loadConfiguration(for: provider)
        }
        .onChange(of: apiKey) { _, _ in didSave = false }
        .onChange(of: model.aiModel) { _, _ in didSave = false }
        .alert("error.title", isPresented: errorPresented) {
            Button("action.ok", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        do {
            guard let credentialKey = model.aiProvider.credentialKey else { return }
            try CredentialStore.set(apiKey, for: credentialKey)
            model.refreshCredentialStatus()
            didSave = true
        } catch {
            errorMessage = (error as? CredentialStoreError)?.localizedDescription(locale: model.language.locale)
                ?? error.localizedDescription
        }
    }

    private func removeCredential() {
        do {
            guard let credentialKey = model.aiProvider.credentialKey else { return }
            try CredentialStore.remove(credentialKey)
            apiKey = ""
            model.refreshCredentialStatus()
            didSave = false
        } catch {
            errorMessage = (error as? CredentialStoreError)?.localizedDescription(locale: model.language.locale)
                ?? error.localizedDescription
        }
    }

    private func loadConfiguration(for provider: AIProvider) {
        apiKey = provider.credentialKey.flatMap { CredentialStore.value(for: $0) } ?? ""
        model.aiModel = model.savedAIModel(for: provider)
        model.refreshCredentialStatus()
        didSave = false
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
