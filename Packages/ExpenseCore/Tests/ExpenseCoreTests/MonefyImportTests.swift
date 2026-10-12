import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

@MainActor
struct MonefyImportTests {
    private typealias F = MonefyFixture
    struct InjectedFailure: Error {}

    let container: ModelContainer
    let context: ModelContext
    let store: ExpenseStore
    let calendar: Calendar
    let food: ExpenseCategory
    let cafe: ExpenseCategory
    let coffee: ExpenseCategory

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        context = ModelContext(container)
        store = ExpenseStore(context: context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Minsk"))
        self.calendar = calendar
        food = try store.addCategory(name: "Продукты", iconName: "cart", colorHex: GouacheTone.shalfey.mainHex)
        cafe = try store.addCategory(name: "Кафе", iconName: "cup", colorHex: GouacheTone.allCases[1].mainHex)
        coffee = try store.addSubcategory(name: "Кофе", iconName: "cup", parent: cafe)
    }

    /// Файл: Food ×3 (две одинаковые траты за день), Coffee ×1, Taxi ×1, доход и перевод.
    private func plan() throws -> MonefyImportPlan {
        MonefyImportPlan(file: try F.parse([
            F.header,
            "3/21/2024,Cash,Food,-10,GBP,-10,GBP,",
            "3/21/2024,Cash,Food,-10,GBP,-10,GBP,",
            "3/22/2024,Cash,Food,-4.5,GBP,-4.5,GBP, Хлеб ",
            "3/23/2024,Card,Coffee,-3.2,GBP,-3.2,GBP,Латте",
            "3/24/2024,Card,Taxi,-12,GBP,-12,GBP,",
            "3/25/2024,Card,Salary,1500,GBP,1500,GBP,",
            "3/25/2024,Card,To 'Cash',-50,GBP,-50,GBP,",
        ]))
    }

    private var fullMapping: [String: MonefyCategoryTarget] {
        ["Food": .category(food.id), "Coffee": .category(coffee.id), "Taxi": .uncategorized]
    }

    private func storedExpenses() throws -> [Expense] {
        try ModelContext(container).fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))
    }

    // MARK: - План

    @Test func planGroupsExpensesByMonefyCategoryLargestFirst() throws {
        let plan = try plan()

        #expect(plan.groups.map(\.name) == ["Food", "Taxi", "Coffee"])
        #expect(plan.groups.map(\.expenseCount) == [3, 1, 1])
        #expect(plan.groups.map(\.totalMinor) == [2450, 1200, 320])
        #expect(plan.period == F.day(2024, 3, 21)...F.day(2024, 3, 24))
        #expect(plan.expenseCount == 5)
        #expect(plan.notExpenseCount == 2)
        #expect(plan.unmappedCount(["Food": .skip]) == 2)
        #expect(plan.importCount(["Food": .skip, "Taxi": .uncategorized]) == 1)
        #expect(plan.importCount(fullMapping) == 5)
    }

    @Test func restoredMappingKeepsOnlyThisFileAndExistingCategories() throws {
        let plan = try plan()
        let deleted = UUID()
        let stored = [
            "Food": MonefyCategoryTarget.category(food.id).storageValue,
            "Coffee": MonefyCategoryTarget.category(deleted).storageValue,
            "Taxi": MonefyCategoryTarget.skip.storageValue,
            "Gym": MonefyCategoryTarget.uncategorized.storageValue,
            "Broken": "мусор",
        ]

        let mapping = plan.restoredMapping(stored, categoryIDs: [food.id, coffee.id])

        #expect(mapping == ["Food": .category(food.id), "Taxi": .skip])
    }

    @Test(arguments: [MonefyCategoryTarget.uncategorized, .skip, .category(UUID())])
    func targetStorageValueRoundTrips(target: MonefyCategoryTarget) {
        #expect(MonefyCategoryTarget(storageValue: target.storageValue) == target)
    }

    // MARK: - Импорт

    @Test func importsMappedExpensesAtNoonOfTheirDay() throws {
        let report = try MonefyImporter.apply(plan(), mapping: fullMapping, store: store, calendar: calendar)

        #expect(report == MonefyImportReport(imported: 5, notExpenses: 2))
        #expect(!context.hasChanges)
        let stored = try storedExpenses()
        #expect(stored.map(\.amountMinor) == [1000, 1000, 450, 320, 1200])
        let categoryIDs: [UUID?] = [food.id, food.id, food.id, coffee.id, nil]
        #expect(stored.map { $0.category?.id } == categoryIDs)
        #expect(stored.map(\.note) == ["", "", "Хлеб", "Латте", ""])
        let noon = try #require(F.day(2024, 3, 22).noon(in: calendar))
        #expect(stored[2].date == noon)
        #expect(calendar.component(.hour, from: stored[2].date) == 12)
    }

    @Test func skippedCategoryIsNotImported() throws {
        var mapping = fullMapping
        mapping["Food"] = .skip

        let report = try MonefyImporter.apply(plan(), mapping: mapping, store: store, calendar: calendar)

        #expect(report == MonefyImportReport(imported: 2, excluded: 3, notExpenses: 2))
        #expect(try storedExpenses().count == 2)
    }

    @Test func importingSameFileTwiceSkipsEverythingAsDuplicates() throws {
        let plan = try plan()
        try MonefyImporter.apply(plan, mapping: fullMapping, store: store, calendar: calendar)

        let again = try MonefyImporter.apply(plan, mapping: fullMapping, store: store, calendar: calendar)

        #expect(again == MonefyImportReport(imported: 0, duplicates: 5, notExpenses: 2))
        #expect(try storedExpenses().count == 5)
    }

    @Test func identicalExpensesInFileAreMatchedOneByOne() throws {
        // В приложении уже одна из двух одинаковых трат 21 марта (записана днём, в другое время).
        let afternoon = try #require(calendar.date(from: DateComponents(year: 2024, month: 3, day: 21, hour: 18, minute: 40)))
        try store.addExpense(amountMinor: 1000, date: afternoon, note: "  ", category: food)

        let report = try MonefyImporter.apply(plan(), mapping: fullMapping, store: store, calendar: calendar)

        #expect(report.duplicates == 1)
        #expect(report.imported == 4)
        #expect(try storedExpenses().filter { $0.amountMinor == 1000 }.count == 2)
    }

    @Test func sameExpenseInAnotherCategoryOrDayIsNotDuplicate() throws {
        let dayBefore = try #require(F.day(2024, 3, 23).noon(in: calendar))
        let sameDay = try #require(F.day(2024, 3, 24).noon(in: calendar))
        try store.addExpense(amountMinor: 1200, date: sameDay, category: food)        // Taxi → без категории
        try store.addExpense(amountMinor: 1200, date: dayBefore, category: nil)       // другой день
        try store.addExpense(amountMinor: 320, date: dayBefore, note: "Капучино", category: coffee)  // другая заметка

        let report = try MonefyImporter.apply(plan(), mapping: fullMapping, store: store, calendar: calendar)

        #expect(report.duplicates == 0)
        #expect(report.imported == 5)
    }

    @Test func remappingAfterImportAddsUnderNewCategory() throws {
        let plan = try plan()
        try MonefyImporter.apply(plan, mapping: fullMapping, store: store, calendar: calendar)
        var mapping = fullMapping
        mapping["Taxi"] = .category(cafe.id)

        let report = try MonefyImporter.apply(plan, mapping: mapping, store: store, calendar: calendar)

        #expect(report == MonefyImportReport(imported: 1, duplicates: 4, notExpenses: 2))
    }

    // MARK: - Ошибки и откат

    @Test func unmappedCategoryIsRejectedBeforeAnyChange() throws {
        var mapping = fullMapping
        mapping["Taxi"] = nil

        #expect(throws: MonefyImportError.unmappedCategory("Taxi")) {
            try MonefyImporter.apply(plan(), mapping: mapping, store: store, calendar: calendar)
        }
        #expect(try storedExpenses().isEmpty)
    }

    @Test func missingTargetCategoryIsRejected() throws {
        let gone = UUID()
        var mapping = fullMapping
        mapping["Taxi"] = .category(gone)

        #expect(throws: MonefyImportError.missingCategory(gone)) {
            try MonefyImporter.apply(plan(), mapping: mapping, store: store, calendar: calendar)
        }
        #expect(try storedExpenses().isEmpty)
    }

    @Test func failureRollsBackEveryInsertAndKeepsLoadedObjectsValid() throws {
        let existing = try store.addExpense(amountMinor: 999, date: .now, note: "Было", category: food)

        #expect(throws: InjectedFailure.self) {
            try MonefyImporter.apply(
                plan(), mapping: fullMapping, store: store, calendar: calendar,
                beforeCommit: { throw InjectedFailure() }
            )
        }

        #expect(!context.hasChanges)
        // Проверяем до выборок: они сами обновили бы объекты и скрыли ошибку.
        #expect(food.expenses.map(\.id) == [existing.id])
        #expect(coffee.expenses.isEmpty)
        #expect(try storedExpenses().map(\.id) == [existing.id])
        #expect(try context.fetchCount(FetchDescriptor<Expense>()) == 1)
    }

    @Test func batchRejectsInvalidAmountBeforeAnyChange() throws {
        let valid = ExpenseStore.NewExpense(amountMinor: 100, date: .now, category: food)
        let tooLarge = ExpenseStore.NewExpense(amountMinor: Money.maxAmountMinor + 1, date: .now, category: nil)

        #expect(throws: ExpenseStoreError.invalidAmount) {
            try store.addExpenses([valid, tooLarge])
        }
        #expect(throws: ExpenseStoreError.invalidAmount) {
            try store.addExpenses([ExpenseStore.NewExpense(amountMinor: 0, date: .now, category: nil)])
        }
        #expect(!context.hasChanges)
        #expect(try storedExpenses().isEmpty)
    }
}
