import Foundation

/// Отправка HTTP-запроса. В приложении — `URLSession`, в тестах — заглушка с готовыми ответами.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Запрос к модели, не зависящий от формата API.
public struct ModelRequest: Sendable {
    public enum Part: Sendable, Equatable {
        case text(String)
        case jpeg(Data)
    }

    public var system: String
    /// Содержимое сообщения пользователя: картинки (с подписями) перед текстом.
    public var parts: [Part]
    /// Имя инструмента / схемы ответа.
    public var schemaName: String
    public var schemaDescription: String
    public var schema: JSONValue
    public var maxTokens: Int
    public var timeout: TimeInterval

    public init(
        system: String,
        parts: [Part],
        schemaName: String,
        schemaDescription: String,
        schema: JSONValue,
        maxTokens: Int = 16_000,
        timeout: TimeInterval
    ) {
        self.system = system
        self.parts = parts
        self.schemaName = schemaName
        self.schemaDescription = schemaDescription
        self.schema = schema
        self.maxTokens = maxTokens
        self.timeout = timeout
    }
}

/// Клиент модели: возвращает JSON-объект ответа (байты), уже проверенный как JSON.
public protocol ModelClient: Sendable {
    func complete(_ request: ModelRequest) async throws -> Data
    /// Имена моделей сервера; `nil` — сервер список не отдаёт.
    func listModels() async throws -> [String]?
}

/// Пауза перед автоповтором (в тестах — без ожидания).
public typealias RetrySleeper = @Sendable (TimeInterval) async throws -> Void

public enum RetryDelay {
    /// Не дольше 10 с даже при большом `retry-after`.
    public static let maxDelay: TimeInterval = 10
    public static let fallbackDelay: TimeInterval = 2

    public static let live: RetrySleeper = { seconds in
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
}

/// Общая часть клиентов: отправка, один автоповтор 429/5xx, перевод ошибок в `AssistantError`.
struct ModelHTTP: Sendable {
    let transport: HTTPTransport
    let sleep: RetrySleeper

    struct Response {
        let data: Data
        let status: Int
        var bodyText: String { String(decoding: data, as: UTF8.self) }
    }

    /// Ответ 2xx или 400 (его разбирает клиент: режим совместимости); остальные статусы — ошибка.
    func perform(_ request: URLRequest) async throws -> Response {
        var attempt = 0
        while true {
            let data: Data
            let http: HTTPURLResponse
            do {
                (data, http) = try await transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                throw AssistantError.transport(error)
            }
            let status = http.statusCode
            if (200..<300).contains(status) || status == 400 {
                return Response(data: data, status: status)
            }
            let error = AssistantError.status(status)
            guard attempt == 0, error == .rateLimited || error == .serverUnavailable else { throw error }
            attempt += 1
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init) ?? RetryDelay.fallbackDelay
            try await sleep(min(max(retryAfter, 0), RetryDelay.maxDelay))
        }
    }

    static func jsonRequest(url: URL, headers: [String: String], body: JSONValue, timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try body.encoded()
        return request
    }
}

/// JSON-объект из текста ответа: снимает обёртку ```json, берёт от первой `{` до последней `}`.
enum JSONExtraction {
    static func object(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        let data = Data(text[start...end].utf8)
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return nil }
        return data
    }
}
