import Foundation

/// Черновик траты в шите записи и правки: то, что ввёл пользователь, до сохранения через `ExpenseStore`.
/// Категория — по `id` (категория или подкатегория): свойства моделей SwiftData в черновике не держим.
public struct ExpenseDraft: Equatable, Sendable {
    /// Текст поля суммы, уже приведённый `AmountInput.sanitize`.
    public var amountText: String
    public var categoryID: UUID?
    public var date: EntryDate
    public var note: String

    public init(amountText: String = "", categoryID: UUID? = nil, date: EntryDate = .today, note: String = "") {
        self.amountText = amountText
        self.categoryID = categoryID
        self.date = date
        self.note = note
    }

    /// Сумма; `nil` — поле пустое или ноль: сохранить нельзя (тряска, `add.amount.empty.a11y`).
    public var amountMinor: Int64? { Money.minor(fromInput: amountText) }

    /// Заметка так, как её сохранит `ExpenseStore`.
    public var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Есть ли что потерять при закрытии — тогда спрашиваем «Не сохранять…».
    /// Новая трата — введена сумма или заметка (`add.discard`); правка — отличается от `initial` (`edit.discard`).
    public func hasUnsavedChanges(comparedTo initial: ExpenseDraft, isNew: Bool) -> Bool {
        if isNew {
            return !amountText.isEmpty || !trimmedNote.isEmpty
        }
        return amountMinor != initial.amountMinor
            || categoryID != initial.categoryID
            || date != initial.date
            || trimmedNote != initial.trimmedNote
    }

    /// Быстрая сумма: `units` целых единиц прибавляются к введённой (§4.9).
    /// `false` — переполнение, поле не меняется.
    @discardableResult
    public mutating func addQuickAmount(_ units: Int64, formatter: MoneyFormatter) -> Bool {
        guard let sum = AmountInput.adding(units, to: amountText) else { return false }
        amountText = AmountInput.sanitize(formatter.editingString(fromMinor: sum)).text
        return true
    }

    /// «Ещё одна»: сумма, заметка и категория сбрасываются, дата остаётся — пачка за один день
    /// (§4.9, §8 п. 14: пачка обычно из разных категорий).
    public mutating func resetForNextExpense() {
        amountText = ""
        note = ""
        categoryID = nil
    }
}
