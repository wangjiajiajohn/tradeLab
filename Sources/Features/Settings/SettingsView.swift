import SwiftUI
import UIKit

private struct KeyboardDismissCapture: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissCaptureView {
        KeyboardDismissCaptureView()
    }

    func updateUIView(_ uiView: KeyboardDismissCaptureView, context: Context) {}

    static func dismantleUIView(_ uiView: KeyboardDismissCaptureView, coordinator: ()) {
        uiView.detach()
    }
}

private final class KeyboardDismissCaptureView: UIView, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private lazy var dismissRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window !== installedWindow else { return }
        detach()
        installedWindow = window
        window?.addGestureRecognizer(dismissRecognizer)
    }

    func detach() {
        installedWindow?.removeGestureRecognizer(dismissRecognizer)
        installedWindow = nil
    }

    @objc private func dismissKeyboard() {
        installedWindow?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView: UIView? = touch.view
        while let view = touchedView {
            if view is UITextField || view is UITextView {
                return false
            }
            touchedView = view.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

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
                            .contentShape(Rectangle())
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
        case .alpaca:
            model.hasAlpacaCredentials
                ? "Alpaca"
                : AppLocalization.string("status.needs_configuration", locale: locale)
        case .twelveData:
            model.hasTwelveDataCredentials
                ? "Twelve Data"
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
    @State private var showingRemoveCredentialsConfirmation = false
    @FocusState private var isCredentialFieldFocused: Bool

    init(presentsProviderPickerOnAppear: Bool = false) {
        self.presentsProviderPickerOnAppear = presentsProviderPickerOnAppear
    }

    private var canSave: Bool {
        switch model.marketDataSource {
        case .offline: false
        case .longbridge:
            !appKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !appSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .alpaca:
            !appKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !appSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .twelveData:
            !appKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
                    providerDescription(model.marketDataSource)
                ))
            }

            if model.marketDataSource != .offline {
                Section("provider.credentials") {
                    credentialFields
                }
                Section {
                    Label("provider.keychain_note", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .scrollDismissesKeyboard(.immediately)
        .background(KeyboardDismissCapture())
        .navigationTitle("settings.market_data_provider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.hasSelectedMarketDataCredentials {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingRemoveCredentialsConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(Text("provider.remove_credentials"))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.marketDataSource != .offline {
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
        .onChange(of: model.marketDataSource) { _, _ in loadCredentials() }
        .onChange(of: appKey) { _, _ in didSave = false }
        .onChange(of: appSecret) { _, _ in didSave = false }
        .onChange(of: accessToken) { _, _ in didSave = false }
        .alert("error.title", isPresented: errorPresented) {
            Button("action.ok", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "provider.remove_credentials",
            isPresented: $showingRemoveCredentialsConfirmation,
            titleVisibility: .visible
        ) {
            Button("provider.remove_credentials", role: .destructive) { removeCredentials() }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("provider.remove_credentials.message")
        }
    }

    private var providerPickerMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            providerButton(.offline)
            Divider()
            providerButton(.longbridge)
            Divider()
            providerButton(.alpaca)
            Divider()
            providerButton(.twelveData)
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
        case .alpaca: "provider.alpaca"
        case .twelveData: "provider.twelve_data"
        }
    }

    private func providerDescription(_ source: MarketDataSource) -> String {
        switch source {
        case .offline: "provider.offline.description"
        case .longbridge: "provider.longbridge.description"
        case .alpaca: "provider.alpaca.description"
        case .twelveData: "provider.twelve_data.description"
        }
    }

    @ViewBuilder
    private var credentialFields: some View {
        switch model.marketDataSource {
        case .offline:
            EmptyView()
        case .longbridge:
            TextField("provider.longbridge.app_key", text: $appKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isCredentialFieldFocused)
            SecretEntryField(
                title: "provider.longbridge.app_secret",
                text: $appSecret,
                isFocused: $isCredentialFieldFocused
            )
            SecretEntryField(
                title: "provider.longbridge.access_token",
                text: $accessToken,
                isFocused: $isCredentialFieldFocused
            )
        case .alpaca:
            TextField("provider.alpaca.api_key", text: $appKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isCredentialFieldFocused)
            SecretEntryField(
                title: "provider.alpaca.api_secret",
                text: $appSecret,
                isFocused: $isCredentialFieldFocused
            )
        case .twelveData:
            SecretEntryField(
                title: "provider.twelve_data.api_key",
                text: $appKey,
                isFocused: $isCredentialFieldFocused
            )
        }
    }

    private func loadCredentials() {
        switch model.marketDataSource {
        case .offline:
            appKey = ""
            appSecret = ""
            accessToken = ""
        case .longbridge:
            appKey = CredentialStore.value(for: .longbridgeAppKey) ?? ""
            appSecret = CredentialStore.value(for: .longbridgeAppSecret) ?? ""
            accessToken = CredentialStore.value(for: .longbridgeAccessToken) ?? ""
        case .alpaca:
            appKey = CredentialStore.value(for: .alpacaAPIKey) ?? ""
            appSecret = CredentialStore.value(for: .alpacaAPISecret) ?? ""
            accessToken = ""
        case .twelveData:
            appKey = CredentialStore.value(for: .twelveDataAPIKey) ?? ""
            appSecret = ""
            accessToken = ""
        }
        didSave = false
    }

    private func save() {
        do {
            switch model.marketDataSource {
            case .offline:
                return
            case .longbridge:
                try CredentialStore.set(appKey, for: .longbridgeAppKey)
                try CredentialStore.set(appSecret, for: .longbridgeAppSecret)
                try CredentialStore.set(accessToken, for: .longbridgeAccessToken)
            case .alpaca:
                try CredentialStore.set(appKey, for: .alpacaAPIKey)
                try CredentialStore.set(appSecret, for: .alpacaAPISecret)
            case .twelveData:
                try CredentialStore.set(appKey, for: .twelveDataAPIKey)
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
            switch model.marketDataSource {
            case .offline:
                return
            case .longbridge:
                try CredentialStore.remove(.longbridgeAppKey)
                try CredentialStore.remove(.longbridgeAppSecret)
                try CredentialStore.remove(.longbridgeAccessToken)
            case .alpaca:
                try CredentialStore.remove(.alpacaAPIKey)
                try CredentialStore.remove(.alpacaAPISecret)
            case .twelveData:
                try CredentialStore.remove(.twelveDataAPIKey)
            }
            appKey = ""
            appSecret = ""
            accessToken = ""
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
    @State private var availableModels: [AIModelOption] = []
    @State private var isLoadingModels = false
    @State private var modelLoadMessage: String?
    @State private var showsManualModelEntry = false
    @State private var selectedModelID = ""
    @State private var validatedAPIKey = ""
    @State private var showingRemoveCredentialsConfirmation = false
    @FocusState private var isCredentialFieldFocused: Bool

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canChooseModel: Bool {
        !trimmedAPIKey.isEmpty
            && !availableModels.isEmpty
            && validatedAPIKey == trimmedAPIKey
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
                    SecretEntryField(
                        title: "provider.ai.api_key",
                        text: $apiKey,
                        isFocused: $isCredentialFieldFocused
                    )
                }
                if canChooseModel {
                    Section {
                        Picker("provider.ai.model", selection: $selectedModelID) {
                            Text("provider.ai.choose_model").tag("")
                            ForEach(availableModels) { option in
                                Text(option.displayName).tag(option.id)
                            }
                        }

                        DisclosureGroup("provider.ai.manual_model", isExpanded: $showsManualModelEntry) {
                            TextField("provider.ai.model_id", text: $selectedModelID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($isCredentialFieldFocused)
                                .submitLabel(.done)
                                .onSubmit { saveConfiguration() }
                        }

                        if didSave {
                            Label("status.saved", systemImage: "checkmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }

                        if let modelLoadMessage {
                            Text(modelLoadMessage)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        HStack {
                            Text("provider.ai.model_section")
                            Spacer()
                            Button {
                                Task { await refreshModels() }
                            } label: {
                                if isLoadingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoadingModels)
                            .accessibilityLabel(Text("provider.ai.refresh_models"))
                        }
                    } footer: {
                        Text("provider.ai.model_auto_save")
                    }
                }
                Section {
                    Label("provider.keychain_note", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .scrollDismissesKeyboard(.immediately)
        .background(KeyboardDismissCapture())
        .navigationTitle("settings.ai_provider")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.hasAIAPIKey {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingRemoveCredentialsConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(Text("provider.remove_credentials"))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.aiProvider != .disabled {
                Button {
                    Task { await refreshModels() }
                } label: {
                    Group {
                        if isLoadingModels {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("provider.ai.loading_models")
                            }
                        } else {
                            Label(
                                "provider.ai.verify_and_load",
                                systemImage: "checkmark.shield"
                            )
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(trimmedAPIKey.isEmpty)
                .allowsHitTesting(!isLoadingModels && !trimmedAPIKey.isEmpty)
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
        .onChange(of: selectedModelID) { _, newValue in
            guard availableModels.contains(where: { $0.id == newValue }) else { return }
            saveConfiguration()
        }
        .alert("provider.ai.configuration_error", isPresented: errorPresented) {
            Button("action.ok", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "provider.remove_credentials",
            isPresented: $showingRemoveCredentialsConfirmation,
            titleVisibility: .visible
        ) {
            Button("provider.remove_credentials", role: .destructive) { removeCredential() }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("provider.remove_credentials.message")
        }
    }

    private func saveConfiguration() {
        do {
            let trimmedModel = selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let credentialKey = model.aiProvider.credentialKey,
                  !trimmedAPIKey.isEmpty,
                  !trimmedModel.isEmpty,
                  validatedAPIKey == trimmedAPIKey || showsManualModelEntry
            else { return }
            try CredentialStore.set(trimmedAPIKey, for: credentialKey)
            validatedAPIKey = trimmedAPIKey
            model.aiModel = trimmedModel
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
            validatedAPIKey = ""
            selectedModelID = ""
            model.refreshCredentialStatus()
            didSave = false
        } catch {
            errorMessage = (error as? CredentialStoreError)?.localizedDescription(locale: model.language.locale)
                ?? error.localizedDescription
        }
    }

    private func loadConfiguration(for provider: AIProvider) {
        apiKey = provider.credentialKey.flatMap { CredentialStore.value(for: $0) } ?? ""
        selectedModelID = model.savedAIModel(for: provider)
        availableModels = AIModelCatalogService.cachedModels(for: provider)
        validatedAPIKey = availableModels.isEmpty ? "" : apiKey
        modelLoadMessage = nil
        showsManualModelEntry = availableModels.isEmpty && !selectedModelID.isEmpty
        model.refreshCredentialStatus()
        didSave = false
    }

    @MainActor
    private func refreshModels() async {
        let trimmedKey = trimmedAPIKey
        guard !trimmedKey.isEmpty, model.aiProvider != .disabled else { return }
        isLoadingModels = true
        modelLoadMessage = nil
        defer { isLoadingModels = false }
        do {
            availableModels = try await AIModelCatalogService.fetchModels(
                for: model.aiProvider,
                apiKey: trimmedKey
            )
            validatedAPIKey = trimmedKey
            if availableModels.contains(where: { $0.id == selectedModelID }) {
                saveConfiguration()
            } else {
                if !selectedModelID.isEmpty {
                    modelLoadMessage = AppLocalization.string(
                        "provider.ai.saved_model_unavailable",
                        locale: model.language.locale
                    )
                }
                if let preferredModel = AIModelCatalogService.preferredModel(
                    for: model.aiProvider,
                    from: availableModels
                ) {
                    selectedModelID = preferredModel.id
                    saveConfiguration()
                }
            }
        } catch {
            availableModels = []
            validatedAPIKey = ""
            modelLoadMessage = nil
            if let catalogError = error as? AIModelCatalogError,
               case .invalidCredentials = catalogError {
                errorMessage = AppLocalization.string(
                    "provider.ai.invalid_credentials",
                    locale: model.language.locale
                )
            } else {
                errorMessage = String(
                    format: AppLocalization.string(
                        "provider.ai.verification_error_format",
                        locale: model.language.locale
                    ),
                    error.localizedDescription
                )
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct SecretEntryField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
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
            .focused(isFocused)
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
