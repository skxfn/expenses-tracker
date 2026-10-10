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

    /// Трата по `id`; `nil` — уже удалена.
    public func expense(id: UUID) throws -> Expense? {
        var descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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

    // MARK: - Категории: выборка

    /// Неархивные категории всех уровней в пользовательском порядке.
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

    /// Категории верхнего уровня в пользовательском порядке.
    public func topLevelCategories(includingArchived: Bool = false) throws -> [ExpenseCategory] {
        try (includingArchived ? allCategories() : activeCategories()).filter { $0.parent == nil }
    }

    /// Подкатегории в порядке ступеней оттенков (по созданию).
    public func subcategories(of parent: ExpenseCategory, includingArchived: Bool = false) -> [ExpenseCategory] {
        SubcategoryShades.ordered(parent.children.filter { includingArchived || !$0.isArchived })
    }

    /// Активных категорий верхнего уровня уже `topLevelCategoryLimit`: новую можно добавить только подкатегорией.
    public func isTopLevelLimitReached() throws -> Bool {
        try topLevelCategories().count >= Self.topLevelCategoryLimit
    }

    /// Тоны, занятые активными категориями верхнего уровня, и имя первой из них — для «занят: Транспорт».
    /// Архивные цвет не держат. `category` — редактируемая категория, её тон свободен для неё самой.
    public func occupiedTones(excluding category: ExpenseCategory? = nil) throws -> [GouacheTone: String] {
        var occupied: [GouacheTone: String] = [:]
        for candidate in try topLevelCategories() where candidate.id != category?.id {
            if let tone = GouacheTone(mainHex: candidate.colorHex), occupied[tone] == nil {
                occupied[tone] = candidate.name
            }
        }
        return occupied
    }

    /// Частые категории для шита записи (§4.9): категории и подкатегории по числу трат
    /// за `frequentCategoriesWindowDays` дней до `now` включительно, при равенстве — по свежести
    /// последней траты. Не хватает — дозаполняются категориями верхнего уровня по `sortOrder`,
    /// затем их подкатегориями. Архивные (и подкатегории архивных) не предлагаются.
    public func frequentCategories(limit: Int = 6, now: Date = .now, calendar: Calendar = .current) throws -> [ExpenseCategory] {
        guard limit > 0 else { return [] }
        let start = calendar.date(byAdding: .day, value: -Self.frequentCategoriesWindowDays, to: now) ?? now
        let recent = try context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= start && $0.date <= now }))

        var usage: [UUID: (category: ExpenseCategory, count: Int, latest: Date)] = [:]
        for expense in recent {
            guard let category = expense.category, Self.isOffered(category) else { continue }
            let current = usage[category.id]
            usage[category.id] = (category, (current?.count ?? 0) + 1, max(current?.latest ?? expense.date, expense.date))
        }
        let ranked = usage.values.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            if lhs.latest != rhs.latest { return lhs.latest > rhs.latest }
            return lhs.category.sortOrder < rhs.category.sortOrder
        }
        var result = ranked.prefix(limit).map(\.category)
        if result.count < limit {
            let chosen = Set(result.map(\.id))
            let topLevel = try topLevelCategories()
            let fill = (topLevel + topLevel.flatMap { subcategories(of: $0) }).filter { !chosen.contains($0.id) }
            result += fill.prefix(limit - result.count)
        }
        return result
    }

    // MARK: - Категории: изменения

    /// Добавляет категорию верхнего уровня в конец списка.
    @discardableResult
    public func addCategory(name: String, iconName: String, colorHex: String) throws -> ExpenseCategory {
        try checkTopLevelLimit()
        let name = try validatedName(name, parent: nil, excluding: nil)
        let tone = try validatedTone(colorHex)
        let category = ExpenseCategory(
            name: name,
            iconName: iconName,
            colorHex: tone.mainHex,
            sortOrder: try nextSortOrder()
        )
        context.insert(category)
        try context.save()
        return category
    }

    /// Добавляет подкатегорию. Цвет — тон родителя, ступень — по порядку создания.
    @discardableResult
    public func addSubcategory(name: String, iconName: String, parent: ExpenseCategory) throws -> ExpenseCategory {
        try validateParent(parent, for: nil)
        let name = try validatedName(name, parent: parent, excluding: nil)
        let subcategory = ExpenseCategory(
            name: name,
            iconName: iconName,
            colorHex: parent.colorHex,
            sortOrder: try nextSortOrder()
        )
        context.insert(subcategory)
        // Связь — после insert, как в импорте: новый объект уже принадлежит контексту родителя.
        subcategory.parent = parent
        try context.save()
        return subcategory
    }

    /// Меняет имя, иконку и цвет, родителя не трогает. У подкатегории `colorHex` не используется.
    public func updateCategory(
        _ category: ExpenseCategory,
        name: String,
        iconName: String,
        colorHex: String
    ) throws {
        try updateCategory(category, name: name, iconName: iconName, colorHex: colorHex, parent: category.parent)
    }

    /// Меняет категорию целиком, в том числе тип: `parent == nil` — категория верхнего уровня
    /// (подкатегорию можно поднять, если лимит позволяет), иначе — подкатегория `parent`
    /// (категорию с подкатегориями опустить нельзя). У подкатегории цвет — тон родителя, `colorHex` не используется.
    public func updateCategory(
        _ category: ExpenseCategory,
        name: String,
        iconName: String,
        colorHex: String,
        parent: ExpenseCategory?
    ) throws {
        let isParentChanged = category.parent?.id != parent?.id
        let isPromoted = category.parent != nil && parent == nil
        let tone: GouacheTone?
        if let parent {
            try validateParent(parent, for: category)
            tone = nil
        } else {
            tone = try validatedTone(colorHex)
            if isPromoted, !category.isArchived { try checkTopLevelLimit() }
        }
        let name = try validatedName(name, parent: parent, excluding: category)

        category.parent = parent
        category.name = name
        category.iconName = iconName
        if let parent {
            category.colorHex = parent.colorHex
        } else if let tone {
            category.colorHex = tone.mainHex
            // Подкатегории хранят тон родителя.
            for child in category.children where child.colorHex != tone.mainHex {
                child.colorHex = tone.mainHex
            }
        }
        // В новом списке — в конец: и среди категорий, и в лесенке оттенков сестёр.
        if isParentChanged {
            category.sortOrder = try nextSortOrder()
        }
        try context.save()
    }

    /// Архивная категория пропадает из ввода, но её расходы остаются в статистике.
    public func archiveCategory(_ category: ExpenseCategory) throws {
        category.isArchived = true
        try context.save()
    }

    /// Возвращает категорию в конец списка активных. Имя не должно совпадать с активной категорией
    /// того же уровня; категорию верхнего уровня — только если лимит позволяет.
    public func unarchiveCategory(_ category: ExpenseCategory) throws {
        guard category.isArchived else { return }
        _ = try validatedName(category.name, parent: category.parent, excluding: category)
        if category.parent == nil { try checkTopLevelLimit() }
        category.sortOrder = try nextSortOrder()
        category.isArchived = false
        try context.save()
    }

    /// Перестановка в списке `topLevelCategories()` с семантикой `onMove` из SwiftUI.
    /// `sortOrder` категорий верхнего уровня переписывается подряд: сначала активные, затем архивные.
    /// Подкатегории упорядочены по созданию и не меняются. Индексы вне списка игнорируются (список в UI мог устареть).
    public func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) throws {
        let active = try topLevelCategories()
        guard
            let last = source.last, last < active.count,
            (0...active.count).contains(destination)
        else { return }

        var reordered = active.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertionIndex = destination - source.count(in: 0..<destination)
        reordered.insert(contentsOf: source.map { active[$0] }, at: insertionIndex)

        let archived = try topLevelCategories(includingArchived: true).filter(\.isArchived)
        for (index, category) in (reordered + archived).enumerated() where category.sortOrder != index {
            category.sortOrder = index
        }
        try context.save()
    }

    /// Удаляет категорию вместе с её подкатегориями. Траты (свои и подкатегорий) переносятся
    /// в `target` или остаются без категории (`nil`). Для подкатегории UI по умолчанию передаёт родителя.
    /// `target` не может быть удаляемой категорией или её подкатегорией.
    public func deleteCategory(_ category: ExpenseCategory, reassignTo target: ExpenseCategory?) throws {
        // Копия массива: удаление и смена категории меняют обратные связи.
        let children = Array(category.children)
        let removed = [category] + children
        if let target, removed.contains(where: { $0.id == target.id }) {
            throw ExpenseStoreError.invalidReassignTarget
        }
        let now = Date.now
        // Траты переносятся до удаления: иначе каскад и nullify отработают по старым связям.
        for expense in removed.flatMap({ Array($0.expenses) }) {
            expense.category = target
            expense.updatedAt = now
        }
        for child in children {
            context.delete(child)
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

    // MARK: - Правила

    /// Предел активных категорий верхнего уровня (INTEGRATION §8 п. 12: архивные не считаются,
    /// старые данные сверх предела не трогаются — он только запрещает создавать новые).
    public static let topLevelCategoryLimit = 15

    /// Окно частых категорий, дней (§4.9).
    public static let frequentCategoriesWindowDays = 60

    // MARK: - Внутреннее

    private static let newestFirst = [
        SortDescriptor(\Expense.date, order: .reverse),
        SortDescriptor(\Expense.createdAt, order: .reverse)
    ]

    private static let categoryOrder = [
        SortDescriptor(\ExpenseCategory.sortOrder),
        SortDescriptor(\ExpenseCategory.createdAt)
    ]

    /// Категорию можно предложить при вводе: ни она, ни её родитель не в архиве.
    private static func isOffered(_ category: ExpenseCategory) -> Bool {
        !category.isArchived && category.parent?.isArchived != true
    }

    private func validateAmount(_ amountMinor: Int64) throws {
        guard amountMinor > 0 else { throw ExpenseStoreError.invalidAmount }
    }

    /// Цвет категории — основной тон «Гуаши» (без учёта регистра).
    private func validatedTone(_ colorHex: String) throws -> GouacheTone {
        guard let tone = GouacheTone(mainHex: colorHex) else { throw ExpenseStoreError.invalidColorHex(colorHex) }
        return tone
    }

    private func checkTopLevelLimit() throws {
        if try isTopLevelLimitReached() { throw ExpenseStoreError.categoryLimitReached }
    }

    /// Родитель — категория верхнего уровня и не сама `category`; у `category` не должно быть подкатегорий.
    private func validateParent(_ parent: ExpenseCategory, for category: ExpenseCategory?) throws {
        guard parent.parent == nil, parent.id != category?.id else { throw ExpenseStoreError.invalidParent }
        if let category, !category.children.isEmpty { throw ExpenseStoreError.hasSubcategories }
    }

    private func normalizedNote(_ note: String) -> String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Обрезает пробелы и проверяет уникальность без учёта регистра среди активных категорий
    /// того же уровня (INTEGRATION §8 п. 13): верхнего — между собой, подкатегорий — среди сестёр.
    private func validatedName(_ name: String, parent: ExpenseCategory?, excluding category: ExpenseCategory?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExpenseStoreError.emptyCategoryName }
        let isDuplicate = try activeCategories().contains {
            $0.id != category?.id
                && $0.parent?.id == parent?.id
                && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
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
