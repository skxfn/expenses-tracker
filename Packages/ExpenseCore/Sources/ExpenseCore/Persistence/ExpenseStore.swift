import Foundation
import SwiftData

/// Операции с расходами и категориями. Каждое изменение сразу сохраняется в контекст.
/// Для живых списков в UI удобнее `@Query`; этот класс — единая точка изменений и валидации.
@MainActor
public final class ExpenseStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Расходы

    @discardableResult
    public func addExpense(
        amountMinor: Int64,
        date: Date,
        note: String = "",
        category: ExpenseCategory?
    ) throws -> Expense {
        try validateAmount(amountMinor)
        let expense = Expense(
            amountMinor: amountMinor,
            date: date,
            note: normalizedNote(note),
            category: category
        )
        context.insert(expense)
        try context.save()
        return expense
    }

    public func updateExpense(
        _ expense: Expense,
        amountMinor: Int64,
        date: Date,
        note: String,
        category: ExpenseCategory?
    ) throws {
        try validateAmount(amountMinor)
        expense.amountMinor = amountMinor
        expense.date = date
        expense.note = normalizedNote(note)
        expense.category = category
        expense.updatedAt = .now
        try context.save()
    }

    public func deleteExpense(_ expense: Expense) throws {
        context.delete(expense)
        try context.save()
    }

    /// Расходы с датой в полуинтервале `[start, end)` — как у `Calendar.dateInterval(of:for:)`,
    /// чтобы полночь следующего периода не попадала в текущий. Новые сверху.
    public func expenses(in interval: DateInterval) throws -> [Expense] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: Self.newestFirst
        )
        return try context.fetch(descriptor)
    }

    /// Последние `limit` расходов по дате операции.
    public func recentExpenses(limit: Int) throws -> [Expense] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<Expense>(sortBy: Self.newestFirst)
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    // MARK: - Категории

    /// Неархивные категории в пользовательском порядке — для ввода расхода.
    public func activeCategories() throws -> [ExpenseCategory] {
        let descriptor = FetchDescriptor<ExpenseCategory>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: Self.categoryOrder
        )
        return try context.fetch(descriptor)
    }

    /// Все категории, включая архивные, в пользовательском порядке.
    public func allCategories() throws -> [ExpenseCategory] {
        try context.fetch(FetchDescriptor<ExpenseCategory>(sortBy: Self.categoryOrder))
    }

    /// Добавляет категорию в конец списка.
    @discardableResult
    public func addCategory(name: String, iconName: String, colorHex: String) throws -> ExpenseCategory {
        let name = try validatedName(name, excluding: nil)
        try validateColor(colorHex)
        let category = ExpenseCategory(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            sortOrder: try nextSortOrder()
        )
        context.insert(category)
        try context.save()
        return category
    }

    public func updateCategory(
        _ category: ExpenseCategory,
        name: String,
        iconName: String,
        colorHex: String
    ) throws {
        let name = try validatedName(name, excluding: category)
        try validateColor(colorHex)
        category.name = name
        category.iconName = iconName
        category.colorHex = colorHex
        try context.save()
    }

    /// Архивная категория пропадает из ввода, но её расходы остаются в статистике.
    public func archiveCategory(_ category: ExpenseCategory) throws {
        category.isArchived = true
        try context.save()
    }

    /// Возвращает категорию в конец списка активных. Имя не должно совпадать с активной категорией.
    public func unarchiveCategory(_ category: ExpenseCategory) throws {
        guard category.isArchived else { return }
        _ = try validatedName(category.name, excluding: category)
        category.sortOrder = try nextSortOrder()
        category.isArchived = false
        try context.save()
    }

    /// Перестановка в списке `activeCategories()` с семантикой `onMove` из SwiftUI.
    /// `sortOrder` переписывается подряд: сначала активные, затем архивные.
    /// Индексы вне списка игнорируются (список в UI мог устареть).
    public func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        let active = try activeCategories()
        guard
            let last = source.last, last < active.count,
            (0...active.count).contains(destination)
        else { return }

        var reordered = active.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertionIndex = destination - source.count(in: 0..<destination)
        reordered.insert(contentsOf: source.map { active[$0] }, at: insertionIndex)

        let archived = try allCategories().filter(\.isArchived)
        for (index, category) in (reordered + archived).enumerated() where category.sortOrder != index {
            category.sortOrder = index
        }
        try context.save()
    }

    /// Удаляет категорию. Её расходы переносятся в `target` или остаются без категории (`nil`).
    public func deleteCategory(_ category: ExpenseCategory, reassignTo target: ExpenseCategory?) throws {
        guard target?.id != category.id else { throw ExpenseStoreError.invalidReassignTarget }
        let now = Date.now
        // Копия массива: смена категории меняет и обратную связь `category.expenses`.
        for expense in Array(category.expenses) {
            expense.category = target
            expense.updatedAt = now
        }
        context.delete(category)
        try context.save()
    }

    /// Создаёт базовые категории один раз за всё время жизни установки.
    /// Если пользователь потом удалит все категории, повторно они не появятся.
    /// Если категории уже есть (например, после импорта), только ставит флаг.
    public func seedDefaultCategoriesIfNeeded(defaults: UserDefaults) throws {
        guard !defaults.bool(forKey: SettingsKeys.didSeedDefaultCategories) else { return }
        if try context.fetchCount(FetchDescriptor<ExpenseCategory>()) == 0 {
            for (index, template) in DefaultCategories.all.enumerated() {
                context.insert(ExpenseCategory(
                    name: template.name,
                    iconName: template.iconName,
                    colorHex: template.colorHex,
                    sortOrder: index
                ))
            }
            try context.save()
        }
        // Флаг ставится только после успешного сохранения, чтобы при ошибке повторить попытку.
        defaults.set(true, forKey: SettingsKeys.didSeedDefaultCategories)
    }

    // MARK: - Внутреннее

    private static let newestFirst = [
        SortDescriptor(\Expense.date, order: .reverse),
        SortDescriptor(\Expense.createdAt, order: .reverse)
    ]

    private static let categoryOrder = [
        SortDescriptor(\ExpenseCategory.sortOrder),
        SortDescriptor(\ExpenseCategory.createdAt)
    ]

    private func validateAmount(_ amountMinor: Int64) throws {
        guard amountMinor > 0 else { throw ExpenseStoreError.invalidAmount }
    }

    private func validateColor(_ colorHex: String) throws {
        guard HexColor.isValid(colorHex) else { throw ExpenseStoreError.invalidColorHex(colorHex) }
    }

    private func normalizedNote(_ note: String) -> String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Обрезает пробелы и проверяет уникальность среди активных категорий без учёта регистра.
    private func validatedName(_ name: String, excluding category: ExpenseCategory?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseStoreError.emptyCategoryName }
        let isDuplicate = try activeCategories().contains {
            $0.id != category?.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !isDuplicate else { throw ExpenseStoreError.duplicateCategoryName(trimmed) }
        return trimmed
    }

    private func nextSortOrder() throws -> Int {
        var descriptor = FetchDescriptor<ExpenseCategory>(
            sortBy: [SortDescriptor(\.sortOrder, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.sortOrder ?? -1) + 1
    }
}
