import Foundation
import Observation
import ExpenseCore

/// Состояние формы добавления/редактирования расхода.
@Observable
final class ExpenseFormModel {
    /// `nil` — новый расход.
    let expense: Expense?
    var amountText: String
    var category: ExpenseCategory?
    var date: Date
    var note: String
    var errorMessage: String?
    /// Категория расхода на момент открытия формы — может быть архивной.
    private let initialCategory: ExpenseCategory?

    init(expense: Expense?, formatter: MoneyFormatter, now: Date = .now) {
        self.expense = expense
        amountText = expense.map { formatter.editingString(fromMinor: $0.amountMinor) } ?? ""
        initialCategory = expense?.category
        category = initialCategory
        date = expense?.date ?? now
        note = expense?.note ?? ""
    }

    var isEditing: Bool { expense != nil }

    var amountMinor: Int64? { Money.minor(fromInput: amountText) }

    var canSave: Bool { amountMinor != nil }

    /// Подсказка нужна, когда пользователь что-то ввёл, но это не сумма.
    var showsAmountHint: Bool {
        !amountText.trimmingCharacters(in: .whitespaces).isEmpty && amountMinor == nil
    }

    /// Активные категории для выбора. Архивная категория редактируемого расхода
    /// добавляется в конец, чтобы её можно было оставить или вернуть после снятия выбора.
    func pickerCategories(active: [ExpenseCategory]) -> [ExpenseCategory] {
        guard let initialCategory, !active.contains(where: { $0.id == initialCategory.id }) else { return active }
        return active + [initialCategory]
    }

    /// Повторный тап по выбранной категории снимает выбор.
    func toggle(_ category: ExpenseCategory) {
        self.category = self.category?.id == category.id ? nil : category
    }

    /// `true` — расход сохранён, форму можно закрыть.
    func save(using store: ExpenseStore) -> Bool {
        guard let amountMinor else { return false }
        do {
            if let expense {
                try store.updateExpense(expense, amountMinor: amountMinor, date: date, note: note, category: category)
            } else {
                try store.addExpense(amountMinor: amountMinor, date: date, note: note, category: category)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// `true` — расход удалён, форму можно закрыть.
    func delete(using store: ExpenseStore) -> Bool {
        guard let expense else { return false }
        do {
            try store.deleteExpense(expense)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
