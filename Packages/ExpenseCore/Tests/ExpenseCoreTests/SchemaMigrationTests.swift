import CoreData
import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

/// Миграция настоящего файла хранилища V1 → V2 через `ModelContainerFactory`.
@Suite struct SchemaMigrationTests {
    private struct V1Fixture {
        let cafe: UUID
        let home: UUID
        let food: UUID
        let custom: UUID
        let archived: UUID
        let lunch: UUID
        let uncategorized: UUID
    }

    private struct CategoryState: Equatable {
        let name: String
        let iconName: String
        let colorHex: String
        let sortOrder: Int
        let isArchived: Bool
        let parentID: UUID?
        let childCount: Int
        let expenseCount: Int
    }

    @Test func v1StoreMigratesToV2OnOpen() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ExpenseCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Expenses.store")
        let fixture = try makeV1Store(at: url)

        let migrated = try state(ofStoreAt: url)

        #expect(migrated.categories.count == 5)
        #expect(migrated.categories.values.allSatisfy { $0.parentID == nil && $0.childCount == 0 })
        #expect(migrated.categories[fixture.cafe] == CategoryState(
            name: "Кафе", iconName: "fork-knife-fill", colorHex: GouacheTone.abrikos.mainHex,
            sortOrder: 0, isArchived: false, parentID: nil, childCount: 0, expenseCount: 1
        ))
        #expect(migrated.categories[fixture.home]?.name == "Дом")
        #expect(migrated.categories[fixture.home]?.iconName == "home-4-fill")
        #expect(migrated.categories[fixture.home]?.colorHex == GouacheTone.umbra.mainHex)
        #expect(migrated.categories[fixture.food]?.name == "Продукты")
        #expect(migrated.categories[fixture.food]?.iconName == "basket-fill")
        #expect(migrated.categories[fixture.food]?.colorHex == GouacheTone.shalfey.mainHex)
        #expect(migrated.categories[fixture.custom]?.name == "Кофейни")
        #expect(migrated.categories[fixture.custom]?.iconName == "teacup-fill")
        #expect(migrated.categories[fixture.custom]?.colorHex == GouacheTone.shalfey.mainHex)
        let archived = try #require(migrated.categories[fixture.archived])
        #expect(archived.isArchived)
        #expect(archived.iconName == "more-3-fill")
        #expect(archived.colorHex == GouacheTone.grafit.mainHex)
        // Траты и их связи на месте.
        #expect(migrated.expenseCategories == [fixture.lunch: fixture.cafe, fixture.uncategorized: nil])

        // Повторное открытие уже V2-хранилища ничего не меняет.
        #expect(try state(ofStoreAt: url) == migrated)

        // Самоссылочная связь в перенесённой базе работает: подкатегория сохраняется и читается.
        let subcategoryID = try addSubcategory(to: fixture.cafe, inStoreAt: url)
        let withSubcategory = try state(ofStoreAt: url)
        #expect(withSubcategory.categories[subcategoryID]?.parentID == fixture.cafe)
        #expect(withSubcategory.categories[fixture.cafe]?.childCount == 1)
    }

    // MARK: - Помощники

    /// Хранилище V1 как у установленной версии 1.0: старые цвета, SF Symbols и имена.
    ///
    /// Пишется через Core Data по модели, которую SwiftData строит из `SchemaV1`: экземпляры
    /// `SchemaV1.ExpenseCategory` в одном процессе с V2 (параллельные тесты) SwiftData путает
    /// с V2 по имени сущности и падает на save («not key value coding-compliant for the key "parent"»).
    private func makeV1Store(at url: URL) throws -> V1Fixture {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: SchemaV1.models))
        let container = NSPersistentContainer(name: "ExpensesV1", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let fixture = V1Fixture(
            cafe: UUID(), home: UUID(), food: UUID(), custom: UUID(), archived: UUID(), lunch: UUID(), uncategorized: UUID()
        )
        // Свой приватный контекст: тест идёт не на главном потоке, `viewContext` тут использовать нельзя.
        let context = container.newBackgroundContext()
        try context.performAndWait {
            @discardableResult
            func category(_ id: UUID, _ name: String, icon: String, color: String, order: Int, archived: Bool = false) -> NSManagedObject {
                let object = NSEntityDescription.insertNewObject(forEntityName: "ExpenseCategory", into: context)
                object.setValuesForKeys([
                    "id": id, "name": name, "iconName": icon, "colorHex": color,
                    "sortOrder": order, "isArchived": archived, "createdAt": Date.now
                ])
                return object
            }
            func expense(_ id: UUID, _ amountMinor: Int64, note: String, category: NSManagedObject?) {
                let object = NSEntityDescription.insertNewObject(forEntityName: "Expense", into: context)
                object.setValuesForKeys([
                    "id": id, "amountMinor": amountMinor, "date": Date.now, "note": note,
                    "createdAt": Date.now, "updatedAt": Date.now
                ])
                object.setValue(category, forKey: "category")
            }

            let cafe = category(fixture.cafe, "Кафе и рестораны", icon: "fork.knife", color: "#DD6B20", order: 0)
            category(fixture.home, "Жильё и ЖКХ", icon: "house.fill", color: "#A0674B", order: 1)
            category(fixture.food, "Продукты", icon: "cart.fill", color: "#2E9D63", order: 2)
            // Своя категория с тем же цветом, что у «Продуктов»: в V1 цвета не уникальны.
            category(fixture.custom, "Кофейни", icon: "cup.and.saucer.fill", color: "#2E9D63", order: 3)
            category(fixture.archived, "Старое", icon: "archivebox.fill", color: "#8E8E93", order: 4, archived: true)
            expense(fixture.lunch, 1250, note: "Обед", category: cafe)
            expense(fixture.uncategorized, 300, note: "", category: nil)
            try context.save()
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        return fixture
    }

    private func addSubcategory(to parentID: UUID, inStoreAt url: URL) throws -> UUID {
        let context = ModelContext(try ModelContainerFactory.make(storeURL: url))
        let parent = try #require(try context.fetch(FetchDescriptor<ExpenseCategory>()).first { $0.id == parentID })
        let subcategory = ExpenseCategory(
            name: "Обеды", iconName: "fork-knife-fill", colorHex: parent.colorHex, sortOrder: 9, parent: parent
        )
        context.insert(subcategory)
        try context.save()
        return subcategory.id
    }

    /// Открывает хранилище фабрикой (с планом миграций) и снимает состояние в значения.
    private func state(ofStoreAt url: URL) throws -> (categories: [UUID: CategoryState], expenseCategories: [UUID: UUID?]) {
        let context = ModelContext(try ModelContainerFactory.make(storeURL: url))
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        return (
            Dictionary(uniqueKeysWithValues: categories.map { category in
                (category.id, CategoryState(
                    name: category.name, iconName: category.iconName, colorHex: category.colorHex,
                    sortOrder: category.sortOrder, isArchived: category.isArchived, parentID: category.parent?.id,
                    childCount: category.children.count, expenseCount: category.expenses.count
                ))
            }),
            Dictionary(uniqueKeysWithValues: expenses.map { ($0.id, $0.category?.id) })
        )
    }
}
