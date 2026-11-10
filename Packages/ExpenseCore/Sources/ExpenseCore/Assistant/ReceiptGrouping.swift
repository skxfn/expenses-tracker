import Foundation

/// Как позиции чека становятся тратами. Модель всегда возвращает позиции, группирует код — без повторного запроса.
public enum ReceiptGroupingMode: String, CaseIterable, Sendable {
    /// Одна трата на категорию (по умолчанию).
    case byCategory
    /// Каждая позиция — отдельная трата.
    case perItem
    /// Весь чек — одна трата.
    case single
}

public enum ReceiptGrouping {
    /// Имён позиций в заметке сгруппированной траты.
    public static let namesInNote = 3

    /// Черновики для режима. Позиции без суммы не сливаются: их нужно заполнить по одной.
    public static func drafts(
        from items: [AssistantDraft],
        mode: ReceiptGroupingMode,
        receipt: ReceiptSummary?,
        formatter: MoneyFormatter
    ) -> [AssistantDraft] {
        switch mode {
        case .perItem:
            return items
        case .byCategory:
            return byCategory(items, store: receipt?.store, formatter: formatter)
        case .single:
            return single(items, receipt: receipt, formatter: formatter)
        }
    }

    /// Разница «итог чека − сумма позиций»; `nil` — итога нет, у какой-то позиции нет суммы или всё сходится.
    public static func mismatchMinor(items: [AssistantDraft], receipt: ReceiptSummary?) -> Int64? {
        guard let total = receipt?.totalMinor else { return nil }
        var sum: Int64 = 0
        for item in items {
            guard let amount = item.amountMinor else { return nil }
            let (next, overflow) = sum.addingReportingOverflow(amount)
            guard !overflow else { return nil }
            sum = next
        }
        let difference = total - sum
        return difference == 0 ? nil : difference
    }

    /// Группа «По категориям»: траты разных дней не сливаются.
    private struct GroupKey: Hashable {
        let categoryID: UUID?
        let date: EntryDate
    }

    private static func byCategory(_ items: [AssistantDraft], store: String?, formatter: MoneyFormatter) -> [AssistantDraft] {
        var order: [GroupKey] = []
        var groups: [GroupKey: [AssistantDraft]] = [:]
        var loose: [(position: Int, draft: AssistantDraft)] = []
        for (position, item) in items.enumerated() {
            guard item.amountMinor != nil else {
                loose.append((position, item))
                continue
            }
            let key = GroupKey(categoryID: item.draft.categoryID, date: item.draft.date)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        var result = order.compactMap { key in groups[key].map { merged($0, store: store, formatter: formatter) } }
        for entry in loose {
            result.insert(entry.draft, at: min(entry.position, result.count))
        }
        return result
    }

    private static func single(_ items: [AssistantDraft], receipt: ReceiptSummary?, formatter: MoneyFormatter) -> [AssistantDraft] {
        guard !items.isEmpty else { return [] }
        var whole = merged(items, store: receipt?.store, formatter: formatter)
        if let total = receipt?.totalMinor, whole.amountMinor != total || whole.issues.contains(.amountMissing) {
            whole.draft.amountText = amountText(total, formatter: formatter)
            whole.issues.remove(.amountMissing)
        }
        // Категория чека — та, на которую пришлось больше всего денег.
        var sums: [UUID: Int64] = [:]
        for item in items {
            guard let id = item.draft.categoryID, let amount = item.amountMinor else { continue }
            sums[id, default: 0] += amount
        }
        whole.draft.categoryID = sums.max { $0.value < $1.value }?.key
        if whole.draft.categoryID != nil { whole.issues.remove(.categoryMissing) }
        if let store = receipt?.store { whole.draft.note = AssistantDraftBuilder.shortened(store) }
        return [whole]
    }

    /// Одна трата из нескольких позиций: сумма, дата первой, заметка «Магазин: a, b, c +N».
    /// Если у какой-то позиции нет суммы, поле суммы пустое: частичная сумма записалась бы заниженной.
    private static func merged(_ items: [AssistantDraft], store: String?, formatter: MoneyFormatter) -> AssistantDraft {
        let first = items[0]
        guard items.count > 1 else { return first }
        var total: Int64 = 0
        var missing = false
        for item in items {
            guard let amount = item.amountMinor else {
                missing = true
                continue
            }
            total = total.addingReportingOverflow(amount).overflow ? Money.maxAmountMinor : total + amount
        }
        var issues = items.reduce(into: Set<DraftIssue>()) { $0.formUnion($1.issues) }
        if !missing { issues.remove(.amountMissing) }
        var draft = first.draft
        draft.amountText = !missing && total > 0 ? amountText(min(total, Money.maxAmountMinor), formatter: formatter) : ""
        draft.note = note(for: items, store: store)
        return AssistantDraft(draft: draft, source: items.map(\.source).filter { !$0.isEmpty }.joined(separator: "\n"), issues: issues)
    }

    private static func note(for items: [AssistantDraft], store: String?) -> String {
        let names = items.map(\.draft.note).filter { !$0.isEmpty }
        var text = names.prefix(namesInNote).joined(separator: ", ")
        if names.count > namesInNote { text += " +\(names.count - namesInNote)" }
        if let store, !store.isEmpty { text = text.isEmpty ? store : "\(store): \(text)" }
        return AssistantDraftBuilder.shortened(text)
    }

    /// Текст суммы для поля, как у черновиков `AssistantDraftBuilder`.
    static func amountText(_ minor: Int64, formatter: MoneyFormatter) -> String {
        AmountInput.sanitize(formatter.editingString(fromMinor: minor), separator: formatter.decimalSeparator).text
    }
}
