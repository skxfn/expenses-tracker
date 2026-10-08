import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

@Suite struct BackupImportTests {
    struct InjectedFailure: Error {}

    private func byID<Record>(_ records: [Record], id: (Record) -> UUID) -> [UUID: Record] {
        Dictionary(uniqueKeysWithValues: records.map { (id($0), $0) })
    }

    private func newCategory(_ name: String, sortOrder: Int = 5) -> BackupPayload.CategoryRecord {
        .init(id: UUID(), name: name, iconName: "car", colorHex: "#007AFF", sortOrder: sortOrder, isArchived: false, createdAt: .now)
    }

    private func newExpense(amount: Int64 = 300, categoryID: UUID?) -> BackupPayload.ExpenseRecord {
        .init(id: UUID(), amountMinor: amount, date: .now, note: "Такси 🚕", categoryID: categoryID, createdAt: .now, updatedAt: .now)
    }

    // MARK: - Merge

    @Test func mergeUpdatesExistingAddsNewAndKeepsTheRest() throws {
        let container = try BackupFixture.makeContainer()
        let context = ModelContext(container)
        let seed = try BackupFixture.seed(context)

        var file = try BackupFixture.payload(of: context)
        file.categories.removeAll { $0.id == seed.food.id || $0.id == seed.archived.id }
        var food = BackupPayload.CategoryRecord(seed.food)
        food.name = "Продукты"
        let transport = newCategory("Транспорт")
        file.categories += [food, BackupPayload.CategoryRecord(seed.archived), transport]
        file.expenses.removeAll { $0.id == seed.uncategorized.id || $0.id == seed.coffee.id }
        var coffee = BackupPayload.ExpenseRecord(seed.coffee)
        coffee.amountMinor = 1500
        coffee.categoryID = transport.id
        let taxi = newExpense(categoryID: transport.id)
        file.expenses += [coffee, taxi]

        let report = try BackupImporter.apply(file, to: context, mode: .merge)

        #expect(report.categories == .init(added: 1, updated: 1, unchanged: 1))
        #expect(report.expenses == .init(added: 1, updated: 1, unchanged: 1))
        #expect(!context.hasChanges)
        let stored = try BackupFixture.storedPayload(of: container)
        let categories = byID(stored.categories, id: \.id)
        let expenses = byID(stored.expenses, id: \.id)
        #expect(categories.count == 3)
        #expect(categories[seed.food.id] == food)
        #expect(categories[transport.id] == transport)
        #expect(expenses.count == 4)
        #expect(expenses[seed.coffee.id] == coffee)
        #expect(expenses[taxi.id] == taxi)
        #expect(expenses[seed.uncategorized.id] == BackupPayload.ExpenseRecord(seed.uncategorized))
        // Объекты, загруженные до импорта, видят новые данные.
        #expect(seed.coffee.category?.name == "Транспорт")
        #expect(seed.food.name == "Продукты")
    }

    @Test func mergingSameBackupTwiceChangesNothing() throws {
        let container = try BackupFixture.makeContainer()
        let context = ModelContext(container)
        try BackupFixture.seed(context)
        let before = try BackupFixture.payload(of: context)
        let data = try BackupExporter.exportData(from: context, currencyCode: "BYN", exportedAt: BackupFixture.exportedAt)

        let report = try BackupImporter.apply(try BackupImporter.decode(data), to: context, mode: .merge)

        #expect(report.categories == .init(unchanged: 2))
        #expect(report.expenses == .init(unchanged: 3))
        #expect(try BackupFixture.storedPayload(of: container) == before)
    }

    // MARK: - Replace

    @Test func replaceLeavesExactlyFileContents() throws {
        let container = try BackupFixture.makeContainer()
        let context = ModelContext(container)
        let seed = try BackupFixture.seed(context)

        var food = BackupPayload.CategoryRecord(seed.food)
        food.name = "Продукты"
        let transport = newCategory("Транспорт")
        let taxi = newExpense(categoryID: transport.id)
        let file = BackupPayload(
            exportedAt: BackupFixture.exportedAt,
            currencyCode: "USD",
            categories: [food, transport],
            expenses: [BackupPayload.ExpenseRecord(seed.coffee), taxi]
        )

        let report = try BackupImporter.apply(file, to: context, mode: .replace)

        #expect(report.categories == .init(added: 1, updated: 1, deleted: 1))
        #expect(report.expenses == .init(added: 1, unchanged: 1, deleted: 2))
        #expect(report.currencyCode == "USD")
        let stored = try BackupFixture.storedPayload(of: container)
        #expect(byID(stored.categories, id: \.id) == byID(file.categories, id: \.id))
        #expect(byID(stored.expenses, id: \.id) == byID(file.expenses, id: \.id))
        #expect(seed.coffee.category?.name == "Продукты")
    }

    @Test func replaceWithEmptyBackupErasesEverything() throws {
        let container = try BackupFixture.makeContainer()
        let context = ModelContext(container)
        try BackupFixture.seed(context)

        let report = try BackupImporter.apply(
            BackupPayload(exportedAt: .now, currencyCode: "BYN", categories: [], expenses: []),
            to: context, mode: .replace
        )

        #expect(report.categories == .init(deleted: 2))
        #expect(report.expenses == .init(deleted: 3))
        let stored = try BackupFixture.storedPayload(of: container)
        #expect(stored.categories.isEmpty && stored.expenses.isEmpty)
    }

    // MARK: - Ссылки на категории

    @Test(arguments: [ImportMode.merge, .replace])
    func expenseWithUnknownCategoryIsImportedWithoutCategory(mode: ImportMode) throws {
        let container = try BackupFixture.makeContainer()
        let context = ModelContext(container)
        let seed = try BackupFixture.seed(context)
        // Категория есть только в базе (не в файле) и категория, которой нет нигде.
        let toStored = newExpense(categoryID: seed.food.id)
        let toNowhere = newExpense(categoryID: UUID())
        let file = BackupPayload(exportedAt: .now, currencyCode: "BYN", categories: [], expenses: [toStored, toNowhere])

        let report = try BackupImporter.apply(file, to: context, mode: mode)

        let expenses = byID(try BackupFixture.storedPayload(of: container).expenses, id: \.id)
        #expect(expenses[toNowhere.id]?.categoryID == nil)
        switch mode {
        case .merge:
            // При слиянии категория из базы никуда не девается — ссылка на неё валидна.
            #expect(expenses[toStored.id]?.categoryID == seed.food.id)
            #expect(report.expensesWithMissingCategory == 1)
        case .replace:
            #expect(expenses[toStored.id]?.categoryID == nil)
            #expect(report.expensesWithMissingCategory == 2)
        }
        #expect(expenses[toNowhere.id] != nil)
    }

    // MARK: - Атомарность

    @Test(arguments: [ImportMode.merge, .replace])
    func failureLeavesContextAndStoreUntouched(mode: ImportMode) throws {
        let container = try BackupFixture.makeContainer()
        let context = ModelContext(container)
        let seed = try BackupFixture.seed(context)
        // Несохранённое изменение до импорта не должно потеряться при откате.
        context.insert(ExpenseCategory(name: "Несохранённая", iconName: "star", colorHex: "#FFCC00", sortOrder: 9))
        let before = try BackupFixture.payload(of: context)

        var food = BackupPayload.CategoryRecord(seed.food)
        food.name = "Продукты"
        let transport = newCategory("Транспорт")
        var coffee = BackupPayload.ExpenseRecord(seed.coffee)
        coffee.amountMinor = 777
        coffee.categoryID = transport.id
        let file = BackupPayload(
            exportedAt: .now, currencyCode: "USD",
            categories: [food, transport],
            expenses: [coffee, newExpense(categoryID: transport.id)]
        )

        #expect(throws: InjectedFailure.self) {
            try BackupImporter.apply(file, to: context, mode: mode, beforeCommit: { throw InjectedFailure() })
        }

        #expect(!context.hasChanges)
        // Уже загруженные объекты не держат откатанных значений и ссылок на откатанные вставки.
        // Проверяем до любых fetch в тесте: выборка сама обновила бы их и скрыла ошибку.
        #expect(seed.coffee.amountMinor == 1250)
        #expect(seed.coffee.category?.id == seed.food.id)
        #expect(seed.food.name == "Еда")
        #expect(seed.repair.category?.id == seed.archived.id)
        #expect(seed.food.expenses.map(\.id) == [seed.coffee.id])
        #expect(try BackupFixture.payload(of: context) == before)
        #expect(try BackupFixture.storedPayload(of: container) == before)
    }

    @Test func invalidPayloadIsRejectedBeforeAnyChange() throws {
        let container = try BackupFixture.makeContainer()
        let context = ModelContext(container)
        let seed = try BackupFixture.seed(context)
        let before = try BackupFixture.payload(of: context)
        let broken = newExpense(amount: 0, categoryID: nil)
        let file = BackupPayload(
            exportedAt: .now, currencyCode: "BYN",
            categories: [newCategory("Новая")],
            expenses: [BackupPayload.ExpenseRecord(seed.coffee), broken]
        )

        #expect(throws: BackupError.nonPositiveAmount(expenseID: broken.id)) {
            try BackupImporter.apply(file, to: context, mode: .replace)
        }
        #expect(!context.hasChanges)
        #expect(try BackupFixture.storedPayload(of: container) == before)
    }
}
