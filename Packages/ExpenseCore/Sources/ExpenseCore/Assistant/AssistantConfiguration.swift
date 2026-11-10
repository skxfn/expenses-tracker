import Foundation

/// Формат API сервера модели.
public enum AssistantAPIFormat: String, CaseIterable, Sendable {
    /// Anthropic Messages: `POST {base}/v1/messages` (Claude, шлюзы Claude).
    case anthropic
    /// OpenAI Chat Completions: `POST {base}/chat/completions` (DeepSeek на Munito и т. п.).
    case openAI
}

/// Готовые настройки сервера; ключ пользователь вводит сам.
public enum AssistantPreset: String, CaseIterable, Sendable {
    /// Claude через шлюз, доступный из РБ без VPN (тот же, что в tender_copilot).
    case claude
    /// DeepSeek на Munito (OpenAI-совместимый API, бесплатный тариф flex).
    case deepSeek
    /// Свой адрес, формат и модель.
    case custom

    public var format: AssistantAPIFormat {
        switch self {
        case .claude, .custom: .anthropic
        case .deepSeek: .openAI
        }
    }

    public var baseURL: String {
        switch self {
        case .claude: "https://claude-n-codex.com:8443"
        case .deepSeek: "https://api.munito.ai/inference/v1"
        case .custom: ""
        }
    }

    /// Самая дешёвая из моделей шлюза, которые читают фото (Haiku шлюз не раздаёт).
    public var model: String {
        switch self {
        case .claude: "claude-sonnet-5"
        case .deepSeek: "deepseek-ai/deepseek-v4.1-flash-1017"
        case .custom: ""
        }
    }
}

/// Настройки подключения к модели. Ключ хранится отдельно (`AssistantKeyStore`).
public struct AssistantConfiguration: Equatable, Sendable {
    public var preset: AssistantPreset
    public var format: AssistantAPIFormat
    /// Как ввёл пользователь; нормализуется в `endpointBase`.
    public var baseURL: String
    public var model: String

    public init(preset: AssistantPreset, format: AssistantAPIFormat, baseURL: String, model: String) {
        self.preset = preset
        self.format = format
        self.baseURL = baseURL
        self.model = model
    }

    public init(preset: AssistantPreset) {
        self.init(preset: preset, format: preset.format, baseURL: preset.baseURL, model: preset.model)
    }

    public static let `default` = AssistantConfiguration(preset: .claude)

    /// Модель задана и адрес разбирается.
    public var isComplete: Bool {
        endpointBase != nil && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Адрес без хвостовых `/`; только https. Путь запроса (`v1/messages`, `chat/completions`) дописывает клиент,
    /// поэтому вставленный полный адрес запроса и `/v1` у Anthropic срезаются.
    public var endpointBase: URL? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        let requestPaths = format == .anthropic ? ["/v1/messages", "/v1"] : ["/chat/completions"]
        for path in requestPaths where text.lowercased().hasSuffix(path) {
            text.removeLast(path.count)
        }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty else {
            return nil
        }
        return url
    }

    /// Адрес запроса модели.
    public var completionsURL: URL? {
        switch format {
        case .anthropic: endpointBase?.appending(path: "v1/messages")
        case .openAI: endpointBase?.appending(path: "chat/completions")
        }
    }

    /// Адрес списка моделей.
    public var modelsURL: URL? {
        switch format {
        case .anthropic: endpointBase?.appending(path: "v1/models")
        case .openAI: endpointBase?.appending(path: "models")
        }
    }

    // MARK: - UserDefaults

    public static func load(from defaults: UserDefaults) -> AssistantConfiguration {
        let preset = defaults.string(forKey: SettingsKeys.assistantPreset).flatMap(AssistantPreset.init(rawValue:)) ?? .claude
        let fallback = AssistantConfiguration(preset: preset)
        return AssistantConfiguration(
            preset: preset,
            format: defaults.string(forKey: SettingsKeys.assistantFormat).flatMap(AssistantAPIFormat.init(rawValue:)) ?? fallback.format,
            baseURL: defaults.string(forKey: SettingsKeys.assistantBaseURL) ?? fallback.baseURL,
            model: defaults.string(forKey: SettingsKeys.assistantModel) ?? fallback.model
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(preset.rawValue, forKey: SettingsKeys.assistantPreset)
        defaults.set(format.rawValue, forKey: SettingsKeys.assistantFormat)
        defaults.set(baseURL, forKey: SettingsKeys.assistantBaseURL)
        defaults.set(model, forKey: SettingsKeys.assistantModel)
    }
}

/// Хранилище ключа API. В приложении — Keychain, в тестах — память.
public protocol AssistantKeyStore: Sendable {
    func readKey() throws -> String?
    func saveKey(_ key: String) throws
    func deleteKey() throws
}

/// Ключ в памяти (тесты, витрина).
public final class InMemoryAssistantKeyStore: AssistantKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    public init(key: String? = nil) {
        self.key = key
    }

    public func readKey() throws -> String? { lock.withLock { key } }
    public func saveKey(_ key: String) throws { lock.withLock { self.key = key } }
    public func deleteKey() throws { lock.withLock { key = nil } }
}
