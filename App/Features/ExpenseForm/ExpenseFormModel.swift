import Foundation
import Observation
import ExpenseCore

/// Состояние шита записи и правки траты (макеты 06–08). Правила черновика — `ExpenseDraft`, `AmountInput`,
/// `EntryDate`, `EntryBatch`, `SwatchRow` в Core (с тестами); здесь — снимки категорий и связь с `ExpenseStore`.
@Observable
final class ExpenseFormModel {
    /// `true` — новая трата, `false` — правка.
    let isNew: Bool
    private(set) var draft: ExpenseDraft
    /// Выбранная категория или подкатегория (снимок для подписи и образца).
    private(set) var category: CategoryChoice?
    /// Категория из «Всех категорий» (при правке — категория траты), которой нет среди частых: занимает 6-й образец.
    private(set) var pinned: CategoryChoice?
    /// Частые категории — снимок при открытии: образцы не перескакивают, пока шит открыт.
    let frequent: [CategoryChoice]
    /// Записанные через «Ещё одна»; живут до закрытия шита.
    private(set) var batch = EntryBatch()
    /// Категория траты при открытии правки — показывается во «Всех категориях», даже если она в архиве.
    let initialCategoryID: UUID?
    /// Правка траты, которой уже нет (удалена, пока шит открывался): шит сразу закрывается.
    let isMissing: Bool
    /// Правимая трата; `nil` — новая.
    let expenseID: UUID?
    /// Новая трата, записанная «Сохранить», — для подсветки её строки на главной (save-reward).
    @ObservationIgnored private(set) var savedExpenseID: UUID?

    @ObservationIgnored private let initialDraft: ExpenseDraft
    @ObservationIgnored private let formatter: MoneyFormatter
    @ObservationIgnored private let calendar: Calendar

    init(
        mode: ExpenseSheet.Mode,
        store: ExpenseStore,
        formatter: MoneyFormatter,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.formatter = formatter
        self.calendar = calendar
        let frequentCategories = (try? store.frequentCategories(limit: SwatchRow.frequentCount, now: now, calendar: calendar)) ?? []
        frequent = frequentCategories.map(CategoryChoice.init)

        let initialCategory: CategoryChoice?
        let initial: ExpenseDraft
        switch mode {
        case .add(let day):
            isNew = true
            expenseID = nil
            isMissing = false
            initialCategory = nil
            initial = ExpenseDraft(date: EntryDate.forNewExpense(on: day, now: now, calendar: calendar))
        case .edit(let id):
            isNew = false
            expenseID = id
            let expense = try? store.expense(id: id)
            isMissing = expense == nil
            // Правка показывает и сохраняет подкатегорию (§8 п. 6).
            initialCategory = expense?.category.map(CategoryChoice.init)
            initial = ExpenseDraft(
                amountText: expense.map {
                    AmountInput.sanitize(formatter.editingString(fromMinor: $0.amountMinor), separator: formatter.decimalSeparator).text
                } ?? "",
                categoryID: initialCategory?.id,
                date: .moment(expense?.date ?? now),
                note: expense?.note ?? ""
            )
        }
        draft = initial
        initialDraft = initial
        category = initialCategory
        pinned = initialCategory
        initialCategoryID = initialCategory?.id
    }

    // MARK: - Ввод

    var amountText: String { draft.amountText }

    var note: String {
        get { draft.note }
        set { draft.note = newValue }
    }

    /// Набранный текст суммы после `AmountInput.sanitize`. `true` — отброшен третий знак после запятой
    /// (объявить `add.amount.invalid`).
    @discardableResult
    func updateAmount(_ typed: String) -> Bool {
        let sanitized = AmountInput.sanitize(typed, separator: formatter.decimalSeparator)
        draft.amountText = sanitized.text
        return sanitized.droppedFractionDigits
    }

    /// Быстрая сумма прибавляется к введённой. `false` — переполнение, поле не изменилось.
    @discardableResult
    func addQuickAmount(_ units: Int64) -> Bool {
        draft.addQuickAmount(units, formatter: formatter)
    }

    var canSave: Bool { draft.amountMinor != nil }

    /// Закрытие спрашивает «Не сохранять…», свайп вниз заблокирован.
    var hasUnsavedChanges: Bool {
        draft.hasUnsavedChanges(comparedTo: initialDraft, isNew: isNew)
    }

    // MARK: - Категория

    /// 6 частых + выбранная во «Всех категориях» на месте шестой.
    var swatches: [CategoryChoice] {
        SwatchRow.compose(frequent: frequent, pinned: pinned)
    }

    /// Тап по образцу: выбор; повторный тап по выбранному снимает выбор (трата без категории).
    func toggle(_ choice: CategoryChoice) {
        select(category?.id == choice.id ? nil : choice)
    }

    /// Выбор во «Всех категориях»: категория встаёт на место шестого образца, если её нет среди частых.
    func pick(_ choice: CategoryChoice) {
        pinned = choice
        select(choice)
    }

    private func select(_ choice: CategoryChoice?) {
        category = choice
        draft.categoryID = choice?.id
    }

    // MARK: - Дата

    func dateSegment(now: Date = .now) -> EntryDate.Segment {
        draft.date.segment(now: now, calendar: calendar)
    }

    func resolvedDate(now: Date = .now) -> Date {
        draft.date.resolved(now: now, calendar: calendar)
    }

    func selectToday() {
        draft.date = .today
    }

    func selectYesterday() {
        draft.date = .yesterday
    }

    /// День из шита «Дата траты».
    func pickDate(_ day: Date, now: Date = .now) {
        draft.date = EntryDate.picked(day, now: now, calendar: calendar)
    }

    // MARK: - Сохранение

    /// «Сохранить». Правка без изменений хранилище не трогает. Трату, удалённую за время правки, не воскрешает.
    func save(using store: ExpenseStore, now: Date = .now) throws {
        if isNew {
            savedExpenseID = try insert(using: store, now: now)?.id
        } else if hasUnsavedChanges, let expenseID, let amountMinor = draft.amountMinor,
                  let expense = try store.expense(id: expenseID) {
            try store.updateExpense(
                expense,
                amountMinor: amountMinor,
                date: draft.date.resolved(now: now, calendar: calendar),
                note: draft.note,
                category: try resolvedCategory(using: store)
            )
        }
    }

    /// «Ещё одна»: сохранить и добавить в пакет. Сброс формы — `resetForNextExpense()` после анимации.
    func saveForAnother(using store: ExpenseStore, now: Date = .now) throws {
        guard let saved = try insert(using: store, now: now) else { return }
        batch.append(id: saved.id, amountMinor: saved.amountMinor)
    }

    /// Сумма, заметка и категория сбрасываются, дата остаётся (§4.9, §8 п. 14).
    func resetForNextExpense() {
        draft.resetForNextExpense()
        category = nil
        pinned = nil
    }

    /// Пакет без трат, ожидающих удаления (их строки уже скрыты).
    func visibleBatch(hiding ids: Set<UUID>) -> EntryBatch {
        batch.excluding(ids)
    }

    /// Убрать из пакета траты, удалённые из хранилища (после «Удалить» в «Только что записанных»).
    func pruneBatch(using store: ExpenseStore) {
        batch.keep { id in ((try? store.expense(id: id)) ?? nil) != nil }
    }

    // MARK: - Внутреннее

    private func insert(using store: ExpenseStore, now: Date) throws -> (id: UUID, amountMinor: Int64)? {
        guard let amountMinor = draft.amountMinor else { return nil }
        let expense = try store.addExpense(
            amountMinor: amountMinor,
            date: draft.date.resolved(now: now, calendar: calendar),
            note: draft.note,
            category: try resolvedCategory(using: store)
        )
        return (expense.id, amountMinor)
    }

    /// Модель выбранной категории; удалённая за время записи — трата без категории.
    private func resolvedCategory(using store: ExpenseStore) throws -> ExpenseCategory? {
        guard let id = draft.categoryID else { return nil }
        return try store.allCategories().first { $0.id == id }
    }
}
