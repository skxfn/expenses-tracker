import Foundation
import ExpenseCore

extension AssistantModel {
    /// Модель шита. DEBUG: `-assistantStub YES` — ответы-заглушки без сети и ключа;
    /// `-debugAssistant text|receipt` — сразу отправить пример и открыть черновики.
    static func make() -> AssistantModel {
        #if DEBUG
        if AssistantDebug.isStubbed {
            let model = AssistantModel(keyStore: InMemoryAssistantKeyStore(key: "stub"), transport: AssistantDebug.StubTransport())
            if AssistantDebug.scenario == "text" { model.text = AssistantDebug.sampleText }
            return model
        }
        #endif
        return AssistantModel()
    }
}

#if DEBUG
nonisolated enum AssistantDebug {
    static var isStubbed: Bool { UserDefaults.standard.bool(forKey: "assistantStub") }
    /// `text` | `receipt` | nil.
    static var scenario: String? { UserDefaults.standard.string(forKey: "debugAssistant") }
    static let sampleText = "выпил пива 7.50, сходил в компы 12 рублей, вчера такси 9"

    /// Отвечает как шлюз Claude: вызовом инструмента с тратами (`receipt` — позиции чека).
    nonisolated struct StubTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            try await Task.sleep(for: .seconds(1.2))
            let input = AssistantDebug.scenario == "receipt" ? Self.receipt : Self.text
            let body = #"{"content":[{"type":"tool_use","id":"t","name":"record_expenses","input":\#(input)}],"stop_reason":"tool_use"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }

        private static let text = #"""
        {"expenses":[
          {"amount":"7.50","category":"c02","date":null,"note":"Пиво","source":"выпил пива 7.50"},
          {"amount":"12","category":"c07","date":null,"note":"Компьютерный клуб","source":"сходил в компы 12 рублей"},
          {"amount":"9","category":"c03","date":"2026-11-09","note":"Такси","source":"вчера такси 9"},
          {"amount":null,"category":"c01","date":null,"note":"Хлеб","source":"и хлеб"}
        ],"receipt":null,"unparsed":["10 долларов на сувенир"]}
        """#

        private static let receipt = #"""
        {"expenses":[
          {"amount":"2.49","category":"c01","date":null,"note":"Молоко","source":"Молоко 3,2% 1л  1 x 2,49"},
          {"amount":"1.85","category":"c01","date":null,"note":"Хлеб","source":"Хлеб Минский нарезной"},
          {"amount":"6.11","category":"c01","date":null,"note":"Сыр","source":"Сыр Брест-Литовск 200г −0,68"},
          {"amount":"6.57","category":"c01","date":null,"note":"Пиво","source":"Пиво Лидское 0,5л  3 x 2,19"},
          {"amount":"6.16","category":"c01","date":null,"note":"Бананы","source":"Бананы весовые"},
          {"amount":"7.40","category":"c04","date":null,"note":"Fairy","source":"Средство для посуды Fairy"}
        ],"receipt":{"store":"Евроопт","date":"2026-11-08","total":"30.83"},"unparsed":["Бонусов начислено: 0,31"]}
        """#
    }
}
#endif
