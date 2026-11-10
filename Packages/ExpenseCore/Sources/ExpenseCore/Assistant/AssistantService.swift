import Foundation

/// Вход ИИ-записи: текст и/или фото (JPEG/PNG/HEIC — как пришли с камеры или из фотоплёнки).
public struct AssistantInput: Sendable {
    public var text: String
    public var images: [Data]

    public init(text: String = "", images: [Data] = []) {
        self.text = text
        self.images = images
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty
    }
}

/// Окружение разбора: категории, «сегодня», валюта, язык заметок, формат сумм.
public struct AssistantContext: Sendable {
    public let catalog: AssistantCatalog
    public let now: Date
    public let calendar: Calendar
    public let currencyCode: String
    /// `ru` или `en` — на нём модель пишет заметки.
    public let noteLanguage: String
    public let formatter: MoneyFormatter

    public init(catalog: AssistantCatalog, now: Date, calendar: Calendar, currencyCode: String, noteLanguage: String, formatter: MoneyFormatter) {
        self.catalog = catalog
        self.now = now
        self.calendar = calendar
        self.currencyCode = currencyCode
        self.noteLanguage = noteLanguage
        self.formatter = formatter
    }
}

/// Фасад ИИ-записи для App: готовит запрос, выбирает клиент по формату API, собирает черновики.
public struct AssistantService: Sendable {
    public static let textTimeout: TimeInterval = 90
    /// Шлюз Claude временами отвечает по 30–40 с даже на короткий запрос (замер tender_copilot).
    public static let photoTimeout: TimeInterval = 180

    private let client: ModelClient

    public init(client: ModelClient) {
        self.client = client
    }

    public init(configuration: AssistantConfiguration, apiKey: String, transport: HTTPTransport = URLSessionTransport(), sleep: @escaping RetrySleeper = RetryDelay.live) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configuration.isComplete else {
            throw configuration.endpointBase == nil && !configuration.baseURL.trimmingCharacters(in: .whitespaces).isEmpty
                ? AssistantError.invalidBaseURL : AssistantError.notConfigured
        }
        guard !key.isEmpty else { throw AssistantError.notConfigured }
        switch configuration.format {
        case .anthropic:
            client = AnthropicMessagesClient(configuration: configuration, apiKey: key, transport: transport, sleep: sleep)
        case .openAI:
            client = OpenAIChatClient(configuration: configuration, apiKey: key, transport: transport, sleep: sleep)
        }
    }

    /// Разобрать ввод в черновики. Ничего не сохраняет.
    public func parse(_ input: AssistantInput, context: AssistantContext) async throws -> AssistantResult {
        let request = try Self.request(for: input, context: context)
        let json = try await client.complete(request)
        return try AssistantDraftBuilder(catalog: context.catalog, now: context.now, calendar: context.calendar, formatter: context.formatter)
            .build(from: json)
    }

    /// Короткий запрос для «Проверить подключение»: ответил ли сервер по схеме и за сколько.
    public func checkConnection(clock: ContinuousClock = ContinuousClock()) async throws -> Duration {
        let request = ModelRequest(
            system: "Это проверка подключения. Ответь {\"ok\": true}.",
            parts: [.text("Проверка связи.")],
            schemaName: "connection_check",
            schemaDescription: "Подтвердить, что модель на связи.",
            schema: ["type": "object", "additionalProperties": false, "required": ["ok"], "properties": ["ok": ["type": "boolean"]]],
            maxTokens: 2_000,
            timeout: Self.textTimeout
        )
        let start = clock.now
        let json = try await client.complete(request)
        guard (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["ok"] != nil else {
            throw AssistantError.unreadableResponse
        }
        return clock.now - start
    }

    /// Модели сервера (`nil` — сервер список не отдаёт).
    public func availableModels() async throws -> [String]? {
        try await client.listModels()
    }

    static func request(for input: AssistantInput, context: AssistantContext) throws -> ModelRequest {
        let photos = try ReceiptImagePreparer.prepare(input.images)
        var parts: [ModelRequest.Part] = []
        for (photoIndex, photo) in photos.enumerated() {
            for (fragmentIndex, fragment) in photo.fragments.enumerated() {
                parts.append(.text(label(photo: photoIndex, of: photos.count, fragment: fragmentIndex, of: photo.fragments.count)))
                parts.append(.jpeg(fragment))
            }
        }
        parts.append(.text(AssistantPrompt.userText(input.text, hasImages: !photos.isEmpty)))
        let prompt = AssistantPrompt.Context(
            catalog: context.catalog,
            now: context.now,
            calendar: context.calendar,
            currencyCode: context.currencyCode,
            noteLanguage: context.noteLanguage
        )
        return ModelRequest(
            system: AssistantPrompt.system(prompt),
            parts: parts,
            schemaName: AssistantPrompt.toolName,
            schemaDescription: AssistantPrompt.toolDescription,
            schema: AssistantPrompt.schema(categoryKeys: context.catalog.keys),
            timeout: photos.isEmpty ? textTimeout : photoTimeout
        )
    }

    /// «Фото 1 из 2, часть 1 из 3 (части перекрываются):» — подпись перед картинкой.
    static func label(photo: Int, of photoCount: Int, fragment: Int, of fragmentCount: Int) -> String {
        var text = photoCount > 1 ? "Фото \(photo + 1) из \(photoCount)" : "Фото"
        if fragmentCount > 1 { text += ", часть \(fragment + 1) из \(fragmentCount) (части одного фото перекрываются)" }
        return text + ":"
    }
}
