import Foundation

/// Ошибки ИИ-записи. `rawValue` → id текста `error.assistant.<rawValue>` в `copy.json`.
public enum AssistantError: String, Error, Sendable, CaseIterable {
    /// Функция не настроена: нет адреса, модели или ключа.
    case notConfigured
    /// Адрес сервера не https или не разбирается.
    case invalidBaseURL
    case offline
    case timeout
    /// 401, 403.
    case unauthorized
    /// 402: у некоторых шлюзов так выглядит закончившийся баланс.
    case paymentRequired
    /// 404: модели нет на сервере.
    case modelNotFound
    /// 413 или фото больше лимита фрагментов до отправки.
    case tooLarge
    /// Фото не открылось (формат, повреждённый файл).
    case imageUnreadable
    /// 429 после автоповтора.
    case rateLimited
    /// 5xx, 529 после автоповтора.
    case serverUnavailable
    /// Прочие 4xx.
    case badRequest
    /// Модель отказалась отвечать (`refusal`, `content_filter`).
    case refused
    /// Ответ обрезан по `max_tokens`.
    case truncated
    /// Ответ не разобран как JSON нужного вида.
    case unreadableResponse
    /// Модель не нашла ни одной траты.
    case nothingFound

    /// Повтор того же запроса имеет смысл (кнопка «Повторить»).
    public var isRetryable: Bool {
        switch self {
        case .offline, .timeout, .rateLimited, .serverUnavailable, .unreadableResponse: true
        default: false
        }
    }

    /// Исправляется в настройках (кнопка «Настройки»).
    public var needsSettings: Bool {
        switch self {
        case .notConfigured, .invalidBaseURL, .unauthorized, .paymentRequired, .modelNotFound: true
        default: false
        }
    }

    /// Ошибка по HTTP-статусу ответа (не 2xx).
    static func status(_ code: Int) -> AssistantError {
        switch code {
        case 401, 403: .unauthorized
        case 402: .paymentRequired
        case 404: .modelNotFound
        case 408: .timeout
        case 413: .tooLarge
        case 429: .rateLimited
        case 500...599: .serverUnavailable
        default: .badRequest
        }
    }

    /// Ошибка сети `URLSession`.
    static func transport(_ error: Error) -> AssistantError {
        guard let urlError = error as? URLError else { return .offline }
        switch urlError.code {
        case .timedOut: return .timeout
        case .badURL, .unsupportedURL: return .invalidBaseURL
        default: return .offline
        }
    }
}
