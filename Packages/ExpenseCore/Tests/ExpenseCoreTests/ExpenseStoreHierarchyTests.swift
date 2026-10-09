import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

/// Правила категорий и подкатегорий в `ExpenseStore` (INTEGRATION §4.4, §4.9, §8 п. 3, 12, 13).
@MainActor
struct ExpenseStoreHierarchyTests {
    let container: ModelContainer
    let context: ModelContext
    let store: ExpenseStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        context = ModelContext(container)
        store = ExpenseStore(context: context)
    }

    @discardableResult
    private func category(_ name: String, tone: GouacheTone = .grafit) throws -> ExpenseCategory {
        try store.addCategory(name: name, iconName: "tag-fill", colorHex: tone.mainHex)
    }

    @discardableResult
    private func subcategory(_ name: String, of parent: ExpenseCategory) throws -> ExpenseCategory {
        try store.addSubcategory(name: name, iconName: "tag-fill", parent: parent)
    }

    // MARK: - Лимит 15

    @Test func topLevelLimitIgnoresArchivedAndSubcategories() throws {
        var categories: [ExpenseCategory] = []
        for index in 1...15 {
            categories.append(try category("К\(index)"))
        }
        #expect(try store.isTopLevelLimitReached())
        #expect(throws: ExpenseStoreError.categoryLimitReached) { try category("Лишняя") }

        // Подкатегории в лимит не входят.
        try subcategory("Обеды", of: categories[0])
        // Архивная место не держит.
        try store.archiveCategory(categories[1])
        #expect(try !store.isTopLevelLimitReached())
        let sixteenth = try category("Новая")

        // Вернуть из архива при 15 активных нельзя.
        #expect(throws: ExpenseStoreError.categoryLimitReached) { try store.unarchiveCategory(categories[1]) }
        #expect(categories[1].isArchived)
        #expect(sixteenth.parent == nil)
    }

    @Test func promotingSubcategoryRespectsLimit() throws {
        var categories: [ExpenseCategory] = []
        for index in 1...15 {
            categories.append(try category("К\(index)"))
        }
        let lunch = try subcategory("Обеды", of: categories[0])

        #expect(throws: ExpenseStoreError.categoryLimitReached) {
            try store.updateCategory(lunch, name: "Обеды", iconName: "tag-fill", colorHex: GouacheTone.kobalt.mainHex, parent: nil)
        }
        #expect(lunch.parent?.id == categories[0].id)

        try store.archiveCategory(categories[14])
        try store.updateCategory(lunch, name: "Обеды", iconName: "tag-fill", colorHex: GouacheTone.kobalt.mainHex, parent: nil)
        #expect(lunch.parent == nil)
        #expect(lunch.colorHex == GouacheTone.kobalt.mainHex)
        #expect(try store.topLevelCategories().last?.id == lunch.id)
    }

    // MARK: - Подкатегории и смена типа

    @Test func subcategoryTakesParentToneAndOnlyTopLevelParent() throws {
        let cafe = try category("Кафе", tone: .abrikos)
        let lunch = try subcategory("Обеды", of: cafe)

        #expect(lunch.parent?.id == cafe.id)
        #expect(lunch.colorHex == GouacheTone.abrikos.mainHex)
        #expect(cafe.children.map(\.id) == [lunch.id])
        #expect(throws: ExpenseStoreError.invalidParent) { try subcategory("Бизнес-ланч", of: lunch) }
    }

    @Test func changingParentToneRecolorsSubcategories() throws {
        let cafe = try category("Кафе", tone: .abrikos)
        let lunch = try subcategory("Обеды", of: cafe)

        try store.updateCategory(cafe, name: "Кафе", iconName: "fork-knife-fill", colorHex: GouacheTone.okhra.mainHex)

        #expect(cafe.colorHex == GouacheTone.okhra.mainHex)
        #expect(lunch.colorHex == GouacheTone.okhra.mainHex)
    }

    @Test func typeSwitchRules() throws {
        let cafe = try category("Кафе", tone: .abrikos)
        let food = try category("Продукты", tone: .shalfey)
        let lunch = try subcategory("Обеды", of: cafe)

        // Категорию с подкатегориями нельзя сделать подкатегорией.
        #expect(throws: ExpenseStoreError.hasSubcategories) {
            try store.updateCategory(cafe, name: "Кафе", iconName: "tag-fill", colorHex: "", parent: food)
        }
        // Сама в себя и в подкатегорию — нельзя.
        #expect(throws: ExpenseStoreError.invalidParent) {
            try store.updateCategory(food, name: "Продукты", iconName: "tag-fill", colorHex: "", parent: food)
        }
        #expect(throws: ExpenseStoreError.invalidParent) {
            try store.updateCategory(food, name: "Продукты", iconName: "tag-fill", colorHex: "", parent: lunch)
        }
        #expect(food.parent == nil)

        // Категорию без подкатегорий можно опустить; цвет — тон нового родителя.
        try store.updateCategory(food, name: "Продукты", iconName: "tag-fill", colorHex: "", parent: cafe)
        #expect(food.parent?.id == cafe.id)
        #expect(food.colorHex == GouacheTone.abrikos.mainHex)
        // Перенесённая встаёт в конец лесенки, оттенки остальных не сдвигаются.
        #expect(store.subcategories(of: cafe).map(\.id) == [lunch.id, food.id])

        // Перенос подкатегории в другую категорию.
        let transport = try category("Транспорт", tone: .kobalt)
        try store.updateCategory(lunch, name: "Обеды", iconName: "tag-fill", colorHex: "", parent: transport)
        #expect(lunch.colorHex == GouacheTone.kobalt.mainHex)
        #expect(store.subcategories(of: cafe).map(\.id) == [food.id])
    }

    // MARK: - Имена

    @Test func namesAreUniqueWithinTheirLevel() throws {
        let cafe = try category("Кафе")
        let food = try category("Продукты")
        try subcategory("Другое", of: cafe)

        // Подкатегория может называться как категория и как подкатегория в другой категории.
        try subcategory("Кафе", of: food)
        try subcategory("другое", of: food)
        try category("Другое")

        #expect(throws: ExpenseStoreError.duplicateCategoryName("ДРУГОЕ")) { try subcategory(" ДРУГОЕ ", of: cafe) }
        #expect(throws: ExpenseStoreError.duplicateCategoryName("кафе")) { try category("кафе") }
    }

    @Test func movingSubcategoryChecksNamesAmongNewSiblings() throws {
        let cafe = try category("Кафе")
        let food = try category("Продукты")
        let cafeOther = try subcategory("Другое", of: cafe)
        try subcategory("Другое", of: food)

        #expect(throws: ExpenseStoreError.duplicateCategoryName("Другое")) {
            try store.updateCategory(cafeOther, name: "Другое", iconName: "tag-fill", colorHex: "", parent: food)
        }
        #expect(cafeOther.parent?.id == cafe.id)
    }

    @Test func colorMustBeGouacheTone() throws {
        #expect(throws: ExpenseStoreError.invalidColorHex("#2E9D63")) {
            try store.addCategory(name: "Еда", iconName: "tag-fill", colorHex: "#2E9D63")
        }
        let food = try store.addCategory(name: "Еда", iconName: "tag-fill", colorHex: "#3e9b6b")
        #expect(food.colorHex == GouacheTone.shalfey.mainHex)
    }

    // MARK: - Удаление

    @Test func deletingSubcategoryMovesExpensesToChosenCategory() throws {
        let cafe = try category("Кафе")
        let lunch = try subcategory("Обеды", of: cafe)
        let expense = try store.addExpense(amountMinor: 900, date: .now, category: lunch)

        try store.deleteCategory(lunch, reassignTo: cafe)

        #expect(expense.category?.id == cafe.id)
        #expect(cafe.children.isEmpty)
        #expect(try store.allCategories().map(\.id) == [cafe.id])
    }

    @Test func deletingCategoryRemovesSubcategoriesAndReassignsAllExpenses() throws {
        let cafe = try category("Кафе")
        let lunch = try subcategory("Обеды", of: cafe)
        let coffee = try subcategory("Кофе", of: cafe)
        let other = try category("Другое")
        let own = try store.addExpense(amountMinor: 100, date: .now, category: cafe)
        let fromLunch = try store.addExpense(amountMinor: 200, date: .now, category: lunch)
        let fromCoffee = try store.addExpense(amountMinor: 300, date: .now, category: coffee)

        #expect(throws: ExpenseStoreError.invalidReassignTarget) { try store.deleteCategory(cafe, reassignTo: lunch) }

        try store.deleteCategory(cafe, reassignTo: other)

        #expect(try store.allCategories().map(\.id) == [other.id])
        #expect([own, fromLunch, fromCoffee].allSatisfy { $0.category?.id == other.id })
        #expect(other.expenses.count == 3)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 3)
    }

    @Test func deletingCategoryWithoutTargetLeavesExpensesUncategorized() throws {
        let cafe = try category("Кафе")
        let lunch = try subcategory("Обеды", of: cafe)
        try store.addExpense(amountMinor: 100, date: .now, category: cafe)
        try store.addExpense(amountMinor: 200, date: .now, category: lunch)

        try store.deleteCategory(cafe, reassignTo: nil)

        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<ExpenseCategory>()) == 0)
        #expect(try fresh.fetch(FetchDescriptor<Expense>()).allSatisfy { $0.category == nil })
    }

    // MARK: - Порядок

    @Test func moveCategoriesReordersTopLevelOnly() throws {
        let a = try category("A")
        let b = try category("B")
        let lunch = try subcategory("Обеды", of: a)
        let lunchOrder = lunch.sortOrder

        try store.moveCategories(fromOffsets: [1], toOffset: 0)

        #expect(try store.topLevelCategories().map(\.id) == [b.id, a.id])
        #expect(lunch.sortOrder == lunchOrder)
    }

    @Test func shadeStepFollowsCreationOrderAndWraps() throws {
        let cafe = try category("Кафе")
        var subcategories: [ExpenseCategory] = []
        for index in 0..<7 {
            subcategories.append(try subcategory("П\(index)", of: cafe))
        }
        try store.archiveCategory(subcategories[1])

        #expect(subcategories.map { SubcategoryShades.step(of: $0) } == [0, 1, 2, 3, 4, 0, 1])
        #expect(SubcategoryShades.step(of: cafe) == nil)
        #expect(store.subcategories(of: cafe).map(\.name) == ["П0", "П2", "П3", "П4", "П5", "П6"])
    }

    // MARK: - Занятость тона

    @Test func archivedCategoriesDoNotHoldTones() throws {
        let transport = try category("Транспорт", tone: .kobalt)
        let old = try category("Старое", tone: .umbra)
        try category("Дубль", tone: .kobalt)
        try subcategory("Такси", of: transport)
        try store.archiveCategory(old)

        #expect(try store.occupiedTones() == [.kobalt: "Транспорт"])
        #expect(try store.occupiedTones(excluding: transport) == [.kobalt: "Дубль"])
    }

    // MARK: - Частые категории

    @Test func frequentCategoriesRankByCountThenRecencyAndFillBySortOrder() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        let calendar = Calendar(identifier: .gregorian)
        let food = try category("Продукты")
        let cafe = try category("Кафе")
        let transport = try category("Транспорт")
        let gifts = try category("Подарки")
        let archived = try category("Архив")
        let lunch = try subcategory("Обеды", of: cafe)
        let coffee = try subcategory("Кофе", of: cafe)
        let hidden = try subcategory("Внутри архива", of: archived)

        // Обеды и Транспорт — по 2 траты, у Транспорта свежее; Продукты — 1; старые траты не считаются.
        try store.addExpense(amountMinor: 100, date: now.addingTimeInterval(-1 * day), category: lunch)
        try store.addExpense(amountMinor: 100, date: now.addingTimeInterval(-2 * day), category: lunch)
        try store.addExpense(amountMinor: 100, date: now.addingTimeInterval(-1), category: transport)
        try store.addExpense(amountMinor: 100, date: now.addingTimeInterval(-3 * day), category: transport)
        try store.addExpense(amountMinor: 100, date: now.addingTimeInterval(-5 * day), category: food)
        for offset in 61...65 {
            try store.addExpense(amountMinor: 100, date: now.addingTimeInterval(-Double(offset) * day), category: gifts)
        }
        // Будущие траты и архивные категории не предлагаются.
        try store.addExpense(amountMinor: 100, date: now.addingTimeInterval(day), category: gifts)
        for _ in 0..<3 {
            try store.addExpense(amountMinor: 100, date: now.addingTimeInterval(-day), category: hidden)
        }
        try store.archiveCategory(archived)

        let frequent = try store.frequentCategories(limit: 6, now: now, calendar: calendar)

        #expect(frequent.map(\.name) == ["Транспорт", "Обеды", "Продукты", "Кафе", "Подарки", "Кофе"])
        #expect(try store.frequentCategories(limit: 2, now: now, calendar: calendar).map(\.id) == [transport.id, lunch.id])
        #expect(try store.frequentCategories(limit: 0, now: now, calendar: calendar).isEmpty)
        #expect(frequent.last?.id == coffee.id)
    }
}
