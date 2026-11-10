import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ExpenseCore

/// HTTP-заглушка: отдаёт ответы по очереди и запоминает запросы.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    enum Reply {
        case json(Int, String, headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? .failure(.cannotConnectToHost) : replies.removeFirst()
        }
        switch reply {
        case .failure(let code):
            throw URLError(code)
        case .json(let status, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (Data(body.utf8), response)
        }
    }

    /// Тело запроса `index` как словарь.
    func body(_ index: Int) throws -> [String: Any] {
        let data = try #require(lock.withLock { requests[index].httpBody })
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    var requestCount: Int { lock.withLock { requests.count } }
}

/// Пауза автоповтора без ожидания, с записью длительностей.
final class RecordingSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var delays: [TimeInterval] = []

    var sleeper: RetrySleeper {
        { [self] seconds in lock.withLock { delays.append(seconds) } }
    }
}

enum AssistantFixture {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Minsk")!
        return calendar
    }

    /// Вторник, 10 ноября 2026, 12:00 по Минску.
    static var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static let food = AssistantCategory(id: UUID(), name: "Продукты")
    static let cafe = AssistantCategory(id: UUID(), name: "Кафе")
    static let bars = AssistantCategory(id: UUID(), name: "Бары", parentName: "Кафе")
    static let fun = AssistantCategory(id: UUID(), name: "Развлечения")
    static let catalog = AssistantCatalog(categories: [food, cafe, bars, fun])

    static let formatter = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "ru_RU"))

    static var context: AssistantContext {
        AssistantContext(catalog: catalog, now: now, calendar: calendar, currencyCode: "BYN", noteLanguage: "ru", formatter: formatter)
    }

    static var builder: AssistantDraftBuilder {
        AssistantDraftBuilder(catalog: catalog, now: now, calendar: calendar, formatter: formatter)
    }

    static func build(_ json: String) throws -> AssistantResult {
        try builder.build(from: Data(json.utf8))
    }

    /// Ответ Anthropic с вызовом инструмента.
    static func anthropicToolReply(_ input: String, stopReason: String = "tool_use", tool: String = "record_expenses") -> String {
        """
        {"content":[{"type":"thinking","thinking":""},{"type":"tool_use","id":"t1","name":"\(tool)","input":\(input)}],"stop_reason":"\(stopReason)"}
        """
    }

    /// Ответ OpenAI с JSON в тексте.
    static func openAIReply(_ content: String, finishReason: String = "stop") -> String {
        let escaped = String(data: try! JSONSerialization.data(withJSONObject: [content], options: [.fragmentsAllowed]), encoding: .utf8)!
            .dropFirst().dropLast()
        return #"{"choices":[{"message":{"role":"assistant","content":\#(escaped)},"finish_reason":"\#(finishReason)"}]}"#
    }

    static let twoExpenses = """
    {"expenses":[{"amount":"7.50","category":"c02","date":null,"note":"Пиво","source":"выпил пива 7.50"},\
    {"amount":"12","category":"c04","date":null,"note":"Компьютерный клуб","source":"сходил в компы 12 рублей"}],\
    "receipt":null,"unparsed":[]}
    """

    /// JPEG заданного размера; `orientation` — EXIF-ориентация (1 — как есть, 6 — поворот на 90°).
    static func jpeg(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func pixelSize(of jpeg: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (try #require(properties[kCGImagePropertyPixelWidth] as? Int), try #require(properties[kCGImagePropertyPixelHeight] as? Int))
    }
}
