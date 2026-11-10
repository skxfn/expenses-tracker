import Foundation
import Observation
import ExpenseCore

/// Черновики от модели на проверке: правка суммы, категории, даты и заметки, режим чека, сверка с итогом.
/// Сохраняет одним `ExpenseStore.addExpenses` — всё или ничего.
@Observable
final class DraftReviewModel {
    let result: AssistantResult
    private(set) var mode: ReceiptGroupingMode
    private(set) var drafts: [AssistantDraft]
    /// Черновики правили — смена режима чека спросит подтверждение (правки пересоберутся из позиций).
    private(set) var hasEdits = false

    @ObservationIgnored private let formatter: MoneyFormatter
    @ObservationIgnored private let defaults: UserDefaults

    init(result: AssistantResult, formatter: MoneyFormatter, defaults: UserDefaults = .standard) {
        self.result = result
        self.formatter = formatter
        self.defaults = defaults
        let mode = defaults.string(forKey: SettingsKeys.assistantReceiptMode).flatMap(ReceiptGroupingMode.init(rawValue:)) ?? .byCategory
        self.mode = mode
        drafts = result.receipt == nil
            ? result.items
            : ReceiptGrouping.drafts(from: result.items, mode: mode, receipt: result.receipt, formatter: formatter)
    }

    var isReceipt: Bool { result.receipt != nil }

    /// Сумма трат к записи (без пустых сумм).
    var totalMinor: Int64 {
        drafts.compactMap(\.amountMinor).reduce(0) { total, amount in
            let (sum, overflow) = total.addingReportingOverflow(amount)
            return overflow ? .max : sum
        }
    }

    /// Итог чека минус то, что записывается; `nil` — сходится, итога нет или не у всех есть сумма.
    var mismatchMinor: Int64? {
        ReceiptGrouping.mismatchMinor(items: drafts, receipt: result.receipt)
    }

    var canSave: Bool {
        !drafts.isEmpty && drafts.allSatisfy { $0.amountMinor != nil }
    }

    func setMode(_ newMode: ReceiptGroupingMode) {
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: SettingsKeys.assistantReceiptMode)
        drafts = ReceiptGrouping.drafts(from: result.items, mode: newMode, receipt: result.receipt, formatter: formatter)
        hasEdits = false
    }

    // MARK: - Правка

    func setAmountText(_ typed: String, for id: UUID) {
        edit(id) { draft in
            draft.draft.amountText = AmountInput.sanitize(typed, separator: formatter.decimalSeparator).text
            if draft.amountMinor == nil {
                draft.issues.insert(.amountMissing)
            } else {
                draft.issues.remove(.amountMissing)
            }
        }
    }

    func setCategory(_ id: UUID?, for draftID: UUID) {
        edit(draftID) { draft in
            draft.draft.categoryID = id
            if id == nil { draft.issues.insert(.categoryMissing) } else { draft.issues.remove(.categoryMissing) }
        }
    }

    func setDate(_ date: EntryDate, for id: UUID) {
        edit(id) { draft in
            draft.draft.date = date
            draft.issues.subtract([.dateAdjusted, .dateOld])
        }
    }

    func setNote(_ note: String, for id: UUID) {
        edit(id) { $0.draft.note = note }
    }

    func remove(_ id: UUID) {
        drafts.removeAll { $0.id == id }
        hasEdits = true
    }

    /// Расхождение с чеком — отдельной тратой без категории (модель пропустила строку).
    func addDifference() {
        guard let difference = mismatchMinor, difference > 0 else { return }
        let text = AmountInput.sanitize(formatter.editingString(fromMinor: difference), separator: formatter.decimalSeparator).text
        let date = drafts.first?.draft.date ?? .today
        let note = result.receipt?.store ?? ""
        drafts.append(AssistantDraft(draft: ExpenseDraft(amountText: text, date: date, note: note), issues: [.categoryMissing]))
        hasEdits = true
    }

    private func edit(_ id: UUID, _ change: (inout AssistantDraft) -> Void) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        change(&drafts[index])
        hasEdits = true
    }

    // MARK: - Сохранение

    /// Все черновики одним сохранением; возвращает id новых трат. Категория, удалённая за время проверки, — без категории.
    func save(using store: ExpenseStore, now: Date = .now, calendar: Calendar = .current) throws -> [UUID] {
        let categories = Dictionary(try store.allCategories().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let expenses = drafts.compactMap { item -> ExpenseStore.NewExpense? in
            guard let amount = item.amountMinor else { return nil }
            return ExpenseStore.NewExpense(
                amountMinor: amount,
                date: item.draft.date.resolved(now: now, calendar: calendar),
                note: item.draft.trimmedNote,
                category: item.draft.categoryID.flatMap { categories[$0] }
            )
        }
        return try store.addExpenses(expenses)
    }
}
