import SwiftUI
import ExpenseCore

/// Строка «ИИ-запись» в настройках: выключена или каким сервером пользуется; ведёт на экран настройки.
struct AssistantSettingsRow: View {
    @AppStorage(SettingsKeys.assistantEnabled) private var isEnabled = false
    @AppStorage(SettingsKeys.assistantPreset) private var presetRaw = AssistantPreset.claude.rawValue

    var body: some View {
        NavigationLink {
            AssistantSettingsView()
        } label: {
            SettingsRow("settings.assistant", value: String(localized: String.LocalizationValue(valueKey)), showsChevron: true)
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
    }

    private var valueKey: String {
        guard isEnabled else { return "settings.assistant.off" }
        return AssistantSettingsModel.presetKey(AssistantPreset(rawValue: presetRaw) ?? .claude)
    }
}

/// Настройки ИИ-записи (`settings.assistant`): включение, сервер (Claude через шлюз, DeepSeek на Munito или свой),
/// ключ в Keychain, проверка подключения. Сноска честно говорит, что и куда уходит.
@Observable
final class AssistantSettingsModel {
    enum CheckState: Equatable {
        case idle
        case checking
        case passed(Duration)
        case failed(AssistantError)
    }

    var configuration: AssistantConfiguration {
        didSet {
            configuration.save(to: defaults)
            if oldValue.baseURL != configuration.baseURL || oldValue.format != configuration.format { models = nil }
            checkState = .idle
        }
    }

    var keyInput = ""
    private(set) var savedKeySuffix: String?
    private(set) var checkState: CheckState = .idle
    /// Модели сервера после проверки (`nil` — не загружались или сервер их не отдаёт).
    private(set) var models: [String]?
    var keyError = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keyStore: AssistantKeyStore

    init(defaults: UserDefaults = .standard, keyStore: AssistantKeyStore = KeychainAssistantKeyStore()) {
        self.defaults = defaults
        self.keyStore = keyStore
        configuration = AssistantConfiguration.load(from: defaults)
        refreshKey()
    }

    static func presetKey(_ preset: AssistantPreset) -> String {
        switch preset {
        case .claude: "settings.assistant.preset.claude"
        case .deepSeek: "settings.assistant.preset.deepSeek"
        case .custom: "settings.assistant.preset.custom"
        }
    }

    /// Пресет подставляет адрес, формат и модель; «Свой» оставляет текущие значения для правки.
    func selectPreset(_ preset: AssistantPreset) {
        guard preset != configuration.preset else { return }
        if preset == .custom {
            configuration.preset = .custom
        } else {
            configuration = AssistantConfiguration(preset: preset)
        }
    }

    func saveKey() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try keyStore.saveKey(key)
            keyInput = ""
            keyError = false
        } catch {
            keyError = true
        }
        refreshKey()
        checkState = .idle
    }

    func deleteKey() {
        try? keyStore.deleteKey()
        refreshKey()
        checkState = .idle
    }

    /// Короткий запрос по схеме; заодно — список моделей сервера для выбора.
    func check() async {
        checkState = .checking
        do {
            let service = try AssistantService(configuration: configuration, apiKey: (try? keyStore.readKey()) ?? "")
            let elapsed = try await service.checkConnection()
            checkState = .passed(elapsed)
            models = try? await service.availableModels()
        } catch {
            checkState = .failed(error as? AssistantError ?? .unreadableResponse)
        }
    }

    private func refreshKey() {
        let key = (try? keyStore.readKey()) ?? nil
        savedKeySuffix = key.flatMap { $0.isEmpty ? nil : String($0.suffix(4)) }
    }
}

struct AssistantSettingsView: View {
    @AppStorage(SettingsKeys.assistantEnabled) private var isEnabled = false
    @State private var model = AssistantSettingsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
                SettingsFootnoted(String(localized: "settings.assistant.footnote")) {
                    SettingsGroup {
                        SettingsRow(title: "settings.assistant.enable") {
                            Toggle(isOn: $isEnabled) { Text("settings.assistant.enable") }
                                .labelsHidden()
                                .tint(Theme.prominent)
                        }
                    }
                }
                serverGroup
                keyGroup
                checkGroup
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas)
        .navigationTitle("settings.assistant")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Группы

    private var serverGroup: some View {
        SettingsGroup(header: "settings.assistant.server") {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                GlassSegmentedControl(
                    title: "settings.assistant.server",
                    selection: Binding(get: { model.configuration.preset }, set: model.selectPreset),
                    items: AssistantPreset.allCases.map { .init(value: $0, title: LocalizedStringKey(AssistantSettingsModel.presetKey($0))) }
                )
                if model.configuration.preset == .custom {
                    GlassSegmentedControl(
                        title: "settings.assistant.format",
                        selection: $model.configuration.format,
                        items: [
                            .init(value: .anthropic, title: "settings.assistant.format.anthropic"),
                            .init(value: .openAI, title: "settings.assistant.format.openAI"),
                        ]
                    )
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
            fieldRow("settings.assistant.baseURL", text: $model.configuration.baseURL, prompt: "https://", keyboard: .URL)
            modelRow
        }
    }

    private var modelRow: some View {
        SettingsRow(title: "settings.assistant.model") {
            HStack(spacing: Theme.Spacing.xs) {
                TextField("settings.assistant.model", text: $model.configuration.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.secondary)
                if let models = model.models, !models.isEmpty {
                    Menu {
                        ForEach(models, id: \.self) { name in
                            Button(name) { model.configuration.model = name }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(Theme.graphic)
                    }
                    .accessibilityLabel(Text("settings.assistant.model.choose"))
                }
            }
        }
    }

    private var keyGroup: some View {
        SettingsGroup(header: "settings.assistant.key") {
            if let suffix = model.savedKeySuffix {
                SettingsRow("settings.assistant.key", value: L10n.format("settings.assistant.key.saved", suffix))
                Button(role: .destructive, action: model.deleteKey) {
                    SettingsRow(title: "settings.assistant.key.delete") { EmptyView() }
                }
                .buttonStyle(.pressable(Motion.PressScale.row))
            } else {
                SettingsRow(title: "settings.assistant.key") {
                    SecureField("settings.assistant.key.placeholder", text: $model.keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .onSubmit(model.saveKey)
                }
                Button(action: model.saveKey) {
                    SettingsRow(title: "settings.assistant.key.save") { EmptyView() }
                }
                .buttonStyle(.pressable(Motion.PressScale.row))
                .disabled(model.keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var checkGroup: some View {
        SettingsGroup {
            Button {
                Task { await model.check() }
            } label: {
                SettingsRow(title: "settings.assistant.check") {
                    switch model.checkState {
                    case .idle:
                        EmptyView()
                    case .checking:
                        ProgressView()
                    case .passed(let duration):
                        Text(verbatim: L10n.format("settings.assistant.check.passed", Self.seconds(duration)))
                            .typeStyle(.callout)
                            .foregroundStyle(Theme.secondary)
                    case .failed:
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Theme.destructive)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.pressable(Motion.PressScale.row))
            .disabled(model.checkState == .checking)
            if case .failed(let error) = model.checkState {
                Text(LocalizedStringKey(AssistantText.errorKey(error)))
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.vertical, Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func fieldRow(_ title: LocalizedStringKey, text: Binding<String>, prompt: String, keyboard: UIKeyboardType) -> some View {
        SettingsRow(title: title) {
            TextField(text: text, prompt: Text(verbatim: prompt)) { Text(title) }
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.secondary)
        }
    }

    /// «3,6» — секунды с одним знаком после запятой, по языку интерфейса.
    private static func seconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return value.formatted(.number.precision(.fractionLength(1)).locale(.app))
    }
}
