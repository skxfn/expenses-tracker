import Foundation

/// Клиент Anthropic Messages API (Claude напрямую или через шлюз).
///
/// Формат ответа держится инструментом: `tools` + `tool_choice: {type: "tool"}` — так работает шлюз
/// tender_copilot (он не принимает assistant-префилл). Модели, которые отвергают принудительный выбор
/// инструмента (400 про `tool_choice`), получают `auto` и требование вызвать инструмент в промпте;
/// если инструмент не вызван — JSON ищется в тексте ответа.
public struct AnthropicMessagesClient: ModelClient {
    public static let apiVersion = "2023-06-01"

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
        let forced = try await http.perform(urlRequest(url: url, body: body(for: request, forcedTool: true), timeout: request.timeout))
        if forced.status == 400 {
            guard forced.bodyText.contains("tool_choice") else { throw AssistantError.badRequest }
            let automatic = try await http.perform(urlRequest(url: url, body: body(for: request, forcedTool: false), timeout: request.timeout))
            guard automatic.status != 400 else { throw AssistantError.badRequest }
            return try Self.parse(automatic.data, toolName: request.schemaName)
        }
        return try Self.parse(forced.data, toolName: request.schemaName)
    }

    public func listModels() async throws -> [String]? {
        guard let url = configuration.modelsURL else { throw AssistantError.invalidBaseURL }
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let response = try await http.perform(request)
        guard response.status == 200 else { return nil }
        return ModelList.ids(in: response.data)
    }

    // MARK: - Запрос

    /// Ключ уходит в обоих заголовках: шлюзы принимают его по-разному (Bearer или x-api-key).
    private var headers: [String: String] {
        [
            "x-api-key": apiKey,
            "authorization": "Bearer \(apiKey)",
            "anthropic-version": Self.apiVersion,
        ]
    }

    private func urlRequest(url: URL, body: JSONValue, timeout: TimeInterval) throws -> URLRequest {
        try ModelHTTP.jsonRequest(url: url, headers: headers, body: body, timeout: timeout)
    }

    func body(for request: ModelRequest, forcedTool: Bool) -> JSONValue {
        var system = request.system
        if !forcedTool {
            system += "\n\nОтветь вызовом инструмента \(request.schemaName)."
        }
        let toolChoice: JSONValue = forcedTool ? ["type": "tool", "name": .string(request.schemaName)] : ["type": "auto"]
        return [
            "model": .string(configuration.model),
            "max_tokens": .number(Decimal(request.maxTokens)),
            "system": .string(system),
            "tools": [[
                "name": .string(request.schemaName),
                "description": .string(request.schemaDescription),
                "input_schema": request.schema,
            ]],
            "tool_choice": toolChoice,
            "messages": [["role": "user", "content": .array(request.parts.map(Self.content))]],
        ]
    }

    private static func content(_ part: ModelRequest.Part) -> JSONValue {
        switch part {
        case .text(let text):
            ["type": "text", "text": .string(text)]
        case .jpeg(let data):
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": .string(data.base64EncodedString())]]
        }
    }

    // MARK: - Ответ

    private struct Response: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
            let name: String?
            let input: JSONValue?
        }

        let content: [Block]?
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    static func parse(_ data: Data, toolName: String) throws -> Data {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw AssistantError.unreadableResponse }
        switch response.stopReason {
        case "refusal": throw AssistantError.refused
        case "max_tokens": throw AssistantError.truncated
        default: break
        }
        let blocks = response.content ?? []
        if let input = blocks.first(where: { $0.type == "tool_use" && $0.name == toolName })?.input,
           case .object = input,
           let encoded = try? input.encoded() {
            return encoded
        }
        let text = blocks.filter { $0.type == "text" }.compactMap(\.text).joined(separator: "\n")
        guard let json = JSONExtraction.object(in: text) else { throw AssistantError.unreadableResponse }
        return json
    }
}

/// Список моделей `GET …/models`: `{"data": [{"id": …}]}` в обоих форматах.
enum ModelList {
    private struct Response: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    static func ids(in data: Data) -> [String]? {
        (try? JSONDecoder().decode(Response.self, from: data))?.data.map(\.id)
    }
}
