import Foundation

/// Что в черновике нужно проверить глазами (подсветка на экране черновиков).
public enum DraftIssue: String, Sendable, Hashable, CaseIterable {
    /// Модель не нашла сумму или она не разобралась — сохранить нельзя, пока не введена.
    case amountMissing
    case categoryMissing
    /// Дата была в будущем — поставлено «сегодня».
    case dateAdjusted
    /// Дата старше года — скорее всего, ошибка распознавания.
    case dateOld
}

/// Черновик траты от модели. Сохраняется только после проверки пользователем.
public struct AssistantDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var draft: ExpenseDraft
    /// Фрагмент ввода или строка чека — для сверки, не сохраняется.
    public var source: String
    public var issues: Set<DraftIssue>
    /// Отмечен для сохранения.
    public var isIncluded: Bool

    public init(id: UUID = UUID(), draft: ExpenseDraft, source: String = "", issues: Set<DraftIssue> = [], isIncluded: Bool = true) {
        self.id = id
        self.draft = draft
        self.source = source
        self.issues = issues
        self.isIncluded = isIncluded
    }

    public var amountMinor: Int64? { draft.amountMinor }
}

/// Сведения о чеке из ответа модели.
public struct ReceiptSummary: Equatable, Sendable {
    public var store: String?
    /// Начало дня чека в календаре пользователя.
    public var day: Date?
    public var totalMinor: Int64?

    public init(store: String? = nil, day: Date? = nil, totalMinor: Int64? = nil) {
        self.store = store
        self.day = day
        self.totalMinor = totalMinor
    }
}

/// Разобранный ответ модели.
public struct AssistantResult: Equatable, Sendable {
    /// Траты в порядке ответа; у чека — позиции (группирует `ReceiptGrouping`).
    public var items: [AssistantDraft]
    public var receipt: ReceiptSummary?
    /// Что модель не превратила в траты.
    public var unparsed: [String]
    /// Сколько трат отброшено сверх `AssistantPrompt.maxExpenses`.
    public var droppedCount: Int

    public init(items: [AssistantDraft], receipt: ReceiptSummary? = nil, unparsed: [String] = [], droppedCount: Int = 0) {
        self.items = items
        self.receipt = receipt
        self.unparsed = unparsed
        self.droppedCount = droppedCount
    }
}

/// Ответ модели как он есть: суммы и даты — строки, разбираются в `AssistantDraftBuilder`.
struct AssistantResponse: Decodable {
    struct Item: Decodable {
        let amount: String?
        let category: String?
        let date: String?
        let note: String
        let source: String

        enum CodingKeys: String, CodingKey { case amount, category, date, note, source }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            amount = container.lenientString(.amount)
            category = container.lenientString(.category)
            date = container.lenientString(.date)
            note = container.lenientString(.note) ?? ""
            source = container.lenientString(.source) ?? ""
        }
    }

    struct Receipt: Decodable {
        let store: String?
        let date: String?
        let total: String?

        enum CodingKeys: String, CodingKey { case store, date, total }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            store = container.lenientString(.store)
            date = container.lenientString(.date)
            total = container.lenientString(.total)
        }
    }

    let expenses: [Item]
    let receipt: Receipt?
    let unparsed: [String]

    enum CodingKeys: String, CodingKey { case expenses, receipt, unparsed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expenses = try container.decodeIfPresent([Item].self, forKey: .expenses) ?? []
        receipt = try? container.decodeIfPresent(Receipt.self, forKey: .receipt)
        unparsed = (try? container.decodeIfPresent([String].self, forKey: .unparsed)) ?? []
    }
}

private extension KeyedDecodingContainer {
    /// Строка, а число — его кратчайшей записью (`7.4` → "7.4"): в режиме `json_object` модели пишут суммы числами.
    func lenientString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite { return String(value) }
        return nil
    }
}
