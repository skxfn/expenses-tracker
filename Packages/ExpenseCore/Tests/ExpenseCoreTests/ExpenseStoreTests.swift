import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

@MainActor
struct ExpenseStoreTests {
    let container: ModelContainer
    let context: ModelContext
    let store: ExpenseStore

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        context = ModelContext(container)
        store = ExpenseStore(context: context)
    }

    // MARK: - Расходы

    @Test func addExpenseTrimsNoteAndSaves() throws {
        let food = try store.addCategory(name: "Еда", iconName: "cart.fill", colorHex: "#2E9D63")
        let date = Date(timeIntervalSince1970: 1_000)

        let expense = try store.addExpense(amountMinor: 1250, date: date, note: "  обед \n", category: food)

        #expect(expense.note == "обед")
        #expect(expense.amountMinor == 1250)
        #expect(expense.date == date)
        #expect(expense.category?.id == food.id)
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)
        #expect(context.hasChanges == false)
    }

    @Test(arguments: [Int64(0), -1, -10_000])
    func addExpenseRejectsNonPositiveAmount(amount: Int64) throws {
        #expect(throws: ExpenseStoreError.invalidAmount) {
            try store.addExpense(amountMinor: amount, date: .now, category: nil)
        }
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)
    }

    @Test func updateExpenseChangesFieldsAndUpdatedAt() throws {
        let food = try store.addCategory(name: "Еда", iconName: "cart.fill", colorHex: "#2E9D63")
        let taxi = try store.addCategory(name: "Такси", iconName: "car.fill", colorHex: "#3E7BE6")
        let expense = try store.addExpense(amountMinor: 100, date: .now, category: food)
        expense.updatedAt = .distantPast
        let newDate = Date(timeIntervalSince1970: 5_000)

        try store.updateExpense(expense, amountMinor: 700, date: newDate, note: " такси ", category: taxi)

        #expect(expense.amountMinor == 700)
        #expect(expense.date == newDate)
        #expect(expense.note == "такси")
        #expect(expense.category?.id == taxi.id)
        #expect(expense.updatedAt > .distantPast)
        #expect(food.expenses.isEmpty)
        #expect(taxi.expenses.count == 1)
    }

    @Test func updateExpenseWithInvalidAmountKeepsExpense() throws {
        let expense = try store.addExpense(amountMinor: 100, date: .now, note: "кофе", category: nil)

        #expect(throws: ExpenseStoreError.invalidAmount) {
            try store.updateExpense(expense, amountMinor: 0, date: .now, note: "", category: nil)
        }
        #expect(expense.amountMinor == 100)
        #expect(expense.note == "кофе")
    }

    @Test func deleteExpenseKeepsCategory() throws {
        let food = try store.addCategory(name: "Еда", iconName: "cart.fill", colorHex: "#2E9D63")
        let expense = try store.addExpense(amountMinor: 100, date: .now, category: food)

        try store.deleteExpense(expense)

        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 0)
        #expect(try store.allCategories().map(\.id) == [food.id])
        #expect(food.expenses.isEmpty)
    }

    @Test func expensesInIntervalAreHalfOpenAndNewestFirst() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let interval = DateInterval(start: start, duration: 86_400)
        try store.addExpense(amountMinor: 1, date: start.addingTimeInterval(-1), note: "до", category: nil)
        try store.addExpense(amountMinor: 2, date: start, note: "начало", category: nil)
        try store.addExpense(amountMinor: 3, date: start.addingTimeInterval(3_600), note: "середина", category: nil)
        try store.addExpense(amountMinor: 4, date: interval.end, note: "конец", category: nil)

        let notes = try store.expenses(in: interval).map(\.note)

        #expect(notes == ["середина", "начало"])
    }

    @Test func recentExpensesReturnsNewestByDate() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        for day in [3, 1, 4, 2] {
            try store.addExpense(
                amountMinor: 100,
                date: base.addingTimeInterval(Double(day) * 86_400),
                note: "\(day)",
                category: nil
            )
        }

        #expect(try store.recentExpenses(limit: 2).map(\.note) == ["4", "3"])
        #expect(try store.recentExpenses(limit: 10).count == 4)
        #expect(try store.recentExpenses(limit: 0).isEmpty)
    }

    // MARK: - Категории

    @Test func addCategoryTrimsNameAndAppendsToEnd() throws {
        let first = try store.addCategory(name: "  Еда ", iconName: "cart.fill", colorHex: "#2E9D63")
        let second = try store.addCategory(name: "Такси", iconName: "car.fill", colorHex: "#3E7BE6")

        #expect(first.name == "Еда")
        #expect(first.sortOrder == 0)
        #expect(second.sortOrder == 1)
        #expect(try store.activeCategories().map(\.name) == ["Еда", "Такси"])
    }

    @Test(arguments: ["", "   ", "\n"])
    func addCategoryRejectsEmptyName(name: String) throws {
        #expect(throws: ExpenseStoreError.emptyCategoryName) {
            try store.addCategory(name: name, iconName: "cart.fill", colorHex: "#2E9D63")
        }
    }

    @Test func addCategoryRejectsDuplicateIgnoringCase() throws {
        try store.addCategory(name: "Продукты", iconName: "cart.fill", colorHex: "#2E9D63")

        #expect(throws: ExpenseStoreError.duplicateCategoryName("пРОДУКТЫ")) {
            try store.addCategory(name: " пРОДУКТЫ ", iconName: "bag.fill", colorHex: "#3E7BE6")
        }
        #expect(try store.allCategories().count == 1)
    }

    @Test func addCategoryAllowsNameOfArchivedCategory() throws {
        let old = try store.addCategory(name: "Кофе", iconName: "cup.and.saucer.fill", colorHex: "#A0674B")
        try store.archiveCategory(old)

        let new = try store.addCategory(name: "кофе", iconName: "cup.and.saucer.fill", colorHex: "#A0674B")

        #expect(try store.activeCategories().map(\.id) == [new.id])
    }

    @Test(arguments: ["2E9D63", "#2E9D6", "#GGGGGG", ""])
    func addCategoryRejectsInvalidColor(hex: String) throws {
        #expect(throws: ExpenseStoreError.invalidColorHex(hex)) {
            try store.addCategory(name: "Еда", iconName: "cart.fill", colorHex: hex)
        }
    }

    @Test func updateCategoryKeepsOwnNameButRejectsOthers() throws {
        let food = try store.addCategory(name: "Еда", iconName: "cart.fill", colorHex: "#2E9D63")
        try store.addCategory(name: "Такси", iconName: "car.fill", colorHex: "#3E7BE6")

        try store.updateCategory(food, name: "ЕДА", iconName: "basket.fill", colorHex: "#DD6B20")
        #expect(food.name == "ЕДА")
        #expect(food.iconName == "basket.fill")
        #expect(food.colorHex == "#DD6B20")

        #expect(throws: ExpenseStoreError.duplicateCategoryName("такси")) {
            try store.updateCategory(food, name: "такси", iconName: "cart.fill", colorHex: "#2E9D63")
        }
        #expect(food.name == "ЕДА")
    }

    @Test func archiveHidesCategoryAndUnarchiveMovesItToEnd() throws {
        let food = try store.addCategory(name: "Еда", iconName: "cart.fill", colorHex: "#2E9D63")
        let taxi = try store.addCategory(name: "Такси", iconName: "car.fill", colorHex: "#3E7BE6")
        let gifts = try store.addCategory(name: "Подарки", iconName: "gift.fill", colorHex: "#C2185B")

        try store.archiveCategory(food)
        #expect(try store.activeCategories().map(\.id) == [taxi.id, gifts.id])
        #expect(try store.allCategories().count == 3)

        try store.unarchiveCategory(food)
        #expect(try store.activeCategories().map(\.id) == [taxi.id, gifts.id, food.id])
    }

    @Test func unarchiveRejectsNameTakenByActiveCategory() throws {
        let old = try store.addCategory(name: "Кофе", iconName: "cup.and.saucer.fill", colorHex: "#A0674B")
        try store.archiveCategory(old)
        try store.addCategory(name: "КОФЕ", iconName: "cup.and.saucer.fill", colorHex: "#A0674B")

        #expect(throws: ExpenseStoreError.duplicateCategoryName("Кофе")) {
            try store.unarchiveCategory(old)
        }
        #expect(old.isArchived)
    }

    @Test(arguments: [
        (IndexSet([0]), 3, ["B", "C", "A", "D"]),
        (IndexSet([3]), 0, ["D", "A", "B", "C"]),
        (IndexSet([0, 2]), 4, ["B", "D", "A", "C"]),
        (IndexSet([1]), 1, ["A", "B", "C", "D"])
    ])
    func moveCategoriesFollowsOnMoveSemantics(source: IndexSet, destination: Int, expected: [String]) throws {
        for name in ["A", "B", "C", "D"] {
            try store.addCategory(name: name, iconName: "tag.fill", colorHex: "#8B8D98")
        }

        try store.moveCategories(fromOffsets: source, toOffset: destination)

        #expect(try store.activeCategories().map(\.name) == expected)
    }

    @Test func moveCategoriesKeepsArchivedAfterActive() throws {
        let archived = try store.addCategory(name: "Архив", iconName: "tag.fill", colorHex: "#8B8D98")
        for name in ["A", "B", "C"] {
            try store.addCategory(name: name, iconName: "tag.fill", colorHex: "#8B8D98")
        }
        try store.archiveCategory(archived)

        try store.moveCategories(fromOffsets: [2], toOffset: 0)

        let all = try store.allCategories()
        #expect(all.map(\.name) == ["C", "A", "B", "Архив"])
        #expect(all.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test func deleteCategoryReassignsExpenses() throws {
        let food = try store.addCategory(name: "Еда", iconName: "cart.fill", colorHex: "#2E9D63")
        let other = try store.addCategory(name: "Другое", iconName: "tag.fill", colorHex: "#8B8D98")
        let expense = try store.addExpense(amountMinor: 100, date: .now, category: food)
        expense.updatedAt = .distantPast

        try store.deleteCategory(food, reassignTo: other)

        #expect(try store.allCategories().map(\.id) == [other.id])
        #expect(expense.category?.id == other.id)
        #expect(expense.updatedAt > .distantPast)
        #expect(other.expenses.count == 1)
    }

    @Test func deleteCategoryWithoutTargetLeavesExpensesUncategorized() throws {
        let food = try store.addCategory(name: "Еда", iconName: "cart.fill", colorHex: "#2E9D63")
        try store.addExpense(amountMinor: 100, date: .now, category: food)
        try store.addExpense(amountMinor: 200, date: .now, category: food)

        try store.deleteCategory(food, reassignTo: nil)

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 2)
        #expect(expenses.allSatisfy { $0.category == nil })
        #expect(try store.allCategories().isEmpty)
    }

    @Test func deleteCategoryRejectsItselfAsTarget() throws {
        let food = try store.addCategory(name: "Еда", iconName: "cart.fill", colorHex: "#2E9D63")

        #expect(throws: ExpenseStoreError.invalidReassignTarget) {
            try store.deleteCategory(food, reassignTo: food)
        }
        #expect(try store.allCategories().count == 1)
    }

    // MARK: - Базовые категории

    @Test func seedCreatesDefaultCategoriesOnce() throws {
        let temporary = try TemporaryDefaults()

        try store.seedDefaultCategoriesIfNeeded(defaults: temporary.defaults)
        try store.seedDefaultCategoriesIfNeeded(defaults: temporary.defaults)

        let categories = try store.activeCategories()
        #expect(categories.map(\.name) == DefaultCategories.all.map(\.name))
        #expect(categories.map(\.sortOrder) == Array(0..<DefaultCategories.all.count))
        #expect(temporary.defaults.bool(forKey: SettingsKeys.didSeedDefaultCategories))
    }

    @Test func seedDoesNotRepeatAfterUserDeletedAllCategories() throws {
        let temporary = try TemporaryDefaults()
        try store.seedDefaultCategoriesIfNeeded(defaults: temporary.defaults)

        for category in try store.allCategories() {
            try store.deleteCategory(category, reassignTo: nil)
        }
        try store.seedDefaultCategoriesIfNeeded(defaults: temporary.defaults)

        #expect(try store.allCategories().isEmpty)
    }

    @Test func seedSkipsWhenCategoriesAlreadyExist() throws {
        let temporary = try TemporaryDefaults()
        try store.addCategory(name: "Своя", iconName: "tag.fill", colorHex: "#8B8D98")

        try store.seedDefaultCategoriesIfNeeded(defaults: temporary.defaults)

        #expect(try store.allCategories().map(\.name) == ["Своя"])
        #expect(temporary.defaults.bool(forKey: SettingsKeys.didSeedDefaultCategories))
    }
}
