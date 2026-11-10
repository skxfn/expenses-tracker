import Foundation

/// Клиент OpenAI Chat Completions (DeepSeek на Munito и другие совместимые серверы).
///
/// Формат ответа — `response_format: json_schema` (strict). Сервер, который его не знает (400 про
/// `response_format`/`json_schema`), получает `json_object`: вид JSON всё равно описан в промпте.
public struct OpenAIChatClient: ModelClient {
    private let configuration: AssistantConfiguration
    private let apiKey: String
    private let http: ModelHTTP

    public init(configuration: AssistantConfiguration, apiKey: String, transport: HTTPTransport, sleep: @escaping RetrySleeper = RetryDelay.live) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.http = ModelHTTP(transport: transport, sleep: sleep)
    }

    public func complete(_ request: ModelRequest) async throws -> Data {
        guard let url = configuration.completionsURL else { throw AssistantError.invalidBaseURL }
        let strict = try await http.perform(urlRequest(url: url, body: body(for: request, strictSchema: true), timeout: request.timeout))
        if strict.status == 400 {
            let text = strict.bodyText
            guard text.contains("response_format") || text.contains("json_schema") else { throw AssistantError.badRequest }
            let loose = try await http.perform(urlRequest(url: url, body: body(for: request, strictSchema: false), timeout: request.timeout))
            guard loose.status != 400 else { throw AssistantError.badRequest }
            return try Self.parse(loose.data)
        }
        return try Self.parse(strict.data)
    }

    public func listModels() async throws -> [String]? {
        guard let url = configuration.modelsURL else { throw AssistantError.invalidBaseURL }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        let response = try await http.perform(request)
        guard response.status == 200 else { return nil }
        return ModelList.ids(in: response.data)
    }

    // MARK: - Запрос

    private func urlRequest(url: URL, body: JSONValue, timeout: TimeInterval) throws -> URLRequest {
        try ModelHTTP.jsonRequest(url: url, headers: ["authorization": "Bearer \(apiKey)"], body: body, timeout: timeout)
    }

    func body(for request: ModelRequest, strictSchema: Bool) -> JSONValue {
        let format: JSONValue = strictSchema
            ? ["type": "json_schema", "json_schema": ["name": .string(request.schemaName), "strict": true, "schema": request.schema]]
            : ["type": "json_object"]
        return [
            "model": .string(configuration.model),
            "max_tokens": .number(Decimal(request.maxTokens)),
            "response_format": format,
            "messages": [
                ["role": "system", "content": .string(request.system)],
                ["role": "user", "content": .array(request.parts.map(Self.content))],
            ],
        ]
    }

    private static func content(_ part: ModelRequest.Part) -> JSONValue {
        switch part {
        case .text(let text):
            ["type": "text", "text": .string(text)]
        case .jpeg(let data):
            ["type": "image_url", "image_url": ["url": .string("data:image/jpeg;base64," + data.base64EncodedString())]]
        }
    }

    // MARK: - Ответ

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let refusal: String?
            }

            let message: Message?
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        let choices: [Choice]?
    }

    static func parse(_ data: Data) throws -> Data {
        guard let choice = (try? JSONDecoder().decode(Response.self, from: data))?.choices?.first else {
            throw AssistantError.unreadableResponse
        }
        switch choice.finishReason {
        case "length": throw AssistantError.truncated
        case "content_filter": throw AssistantError.refused
        default: break
        }
        if let refusal = choice.message?.refusal, !refusal.isEmpty { throw AssistantError.refused }
        guard let json = JSONExtraction.object(in: choice.message?.content ?? "") else { throw AssistantError.unreadableResponse }
        return json
    }
}
