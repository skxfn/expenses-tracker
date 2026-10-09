import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

// MARK: - Общие фикстуры для Backup*Tests

enum BackupFixture {
    /// Дата с долями миллисекунды, как у реального `Date.now`.
    static let baseDate = Date(timeIntervalSinceReferenceDate: 781_000_000.123_456_7)
    static let exportedAt = Date(timeIntervalSinceReferenceDate: 781_100_000.987_654_3)
    static let coffeeNote = "Кофе ☕️ и круассан 🥐 — «вкусно»"

    static func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.make(inMemory: true)
    }

    struct Seed {
        let food: ExpenseCategory
        let archived: ExpenseCategory
        let coffee: Expense
        let repair: Expense
        let uncategorized: Expense
    }

    /// Две категории (одна архивная) и три расхода, один — без категории.
    @discardableResult
    static func seed(_ context: ModelContext) throws -> Seed {
        let food = ExpenseCategory(name: "Еда", iconName: "cart", colorHex: "#34C759", sortOrder: 0, createdAt: baseDate)
        let archived = ExpenseCategory(
            name: "Старое 🗄️", iconName: "archivebox", colorHex: "#8E8E93", sortOrder: 1,
            isArchived: true, createdAt: baseDate.addingTimeInterval(1.000_4)
        )
        context.insert(food)
        context.insert(archived)
        let coffee = Expense(
            amountMinor: 1250, date: baseDate.addingTimeInterval(3600.000_7), note: coffeeNote,
            category: food, createdAt: baseDate.addingTimeInterval(3600.5), updatedAt: baseDate.addingTimeInterval(7200.25)
        )
        let repair = Expense(
            amountMinor: 9_999_999_999, date: baseDate.addingTimeInterval(86_400), note: "Ремонт \"под ключ\" / C:\\путь\nвторая строка",
            category: archived, createdAt: baseDate, updatedAt: baseDate
        )
        let uncategorized = Expense(
            amountMinor: 1, date: baseDate.addingTimeInterval(-86_400.000_49), note: "",
            category: nil, createdAt: baseDate, updatedAt: baseDate
        )
        context.insert(coffee)
        context.insert(repair)
        context.insert(uncategorized)
        try context.save()
        return Seed(food: food, archived: archived, coffee: coffee, repair: repair, uncategorized: uncategorized)
    }

    /// Подкатегория, как её создаёт `ExpenseStore`: тон родителя, связь — после insert.
    @discardableResult
    static func addSubcategory(_ name: String, to parent: ExpenseCategory, in context: ModelContext) throws -> ExpenseCategory {
        let subcategory = ExpenseCategory(
            name: name, iconName: "fork-knife-fill", colorHex: parent.colorHex, sortOrder: 10,
            createdAt: baseDate.addingTimeInterval(5)
        )
        context.insert(subcategory)
        subcategory.parent = parent
        try context.save()
        return subcategory
    }

    static func payload(of context: ModelContext, currencyCode: String = "BYN") throws -> BackupPayload {
        try BackupExporter.makePayload(from: context, currencyCode: currencyCode, exportedAt: exportedAt)
    }

    /// Состояние хранилища глазами нового контекста — без кэша проверяемого.
    static func storedPayload(of container: ModelContainer) throws -> BackupPayload {
        try payload(of: ModelContext(container))
    }
}

// MARK: - Экспорт и round-trip

@Suite struct BackupRoundTripTests {
    @Test func exportThenImportIntoEmptyStoreRestoresIdenticalData() throws {
        let source = try BackupFixture.makeContainer()
        let sourceContext = ModelContext(source)
        let seed = try BackupFixture.seed(sourceContext)
        let data = try BackupExporter.exportData(from: sourceContext, currencyCode: "BYN", exportedAt: BackupFixture.exportedAt)

        let decoded = try BackupImporter.decode(data)
        #expect(decoded == (try BackupFixture.payload(of: sourceContext)))

        let target = try BackupFixture.makeContainer()
        let targetContext = ModelContext(target)
        let report = try BackupImporter.apply(decoded, to: targetContext, mode: .replace)

        #expect(report.categories == .init(added: 2))
        #expect(report.expenses == .init(added: 3))
        #expect(report.expensesWithMissingCategory == 0)
        #expect(report.currencyCode == "BYN")
        #expect(try BackupFixture.storedPayload(of: target) == decoded)

        // Связи, архивность и тексты — явно, на моделях.
        let expenses = try ModelContext(target).fetch(FetchDescriptor<Expense>())
        let byID = Dictionary(uniqueKeysWithValues: expenses.map { ($0.id, $0) })
        let coffee = try #require(byID[seed.coffee.id])
        #expect(coffee.category?.id == seed.food.id)
        #expect(coffee.note == BackupFixture.coffeeNote)
        #expect(coffee.category?.expenses.count == 1)
        let repair = try #require(byID[seed.repair.id])
        #expect(repair.category?.isArchived == true)
        #expect(repair.category?.name == "Старое 🗄️")
        #expect(repair.amountMinor == 9_999_999_999)
        #expect(repair.note == seed.repair.note)
        #expect(try #require(byID[seed.uncategorized.id]).category == nil)
        // Даты совпадают с точностью до миллисекунды.
        #expect(abs(coffee.date.timeIntervalSince(seed.coffee.date)) <= 0.0005)
        #expect(abs(coffee.updatedAt.timeIntervalSince(seed.coffee.updatedAt)) <= 0.0005)
    }

    @Test func jsonIsHumanReadable() throws {
        let context = ModelContext(try BackupFixture.makeContainer())
        try BackupFixture.seed(context)
        let data = try BackupExporter.exportData(from: context, currencyCode: "BYN", exportedAt: BackupFixture.exportedAt)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\n  \"categories\" : ["))
        #expect(json.contains("\"formatVersion\" : 2"))
        // У категорий верхнего уровня `parentID` в файл не пишется.
        #expect(!json.contains("parentID"))
        #expect(json.contains("\"currencyCode\" : \"BYN\""))
        #expect(json.contains("\"exportedAt\" : \"2025-10-02T12:13:20.988Z\""))
        #expect(json.contains("\"createdAt\" : \"2025-10-01T08:26:40.123Z\""))
        // Кириллица и эмодзи — как есть, без \u-экранирования; слэши не экранируются.
        #expect(json.contains(BackupFixture.coffeeNote))
        #expect(json.contains("Ремонт \\\"под ключ\\\" / C:\\\\путь\\nвторая строка"))
        // sortedKeys: ключи верхнего уровня по алфавиту.
        let keys = ["categories", "currencyCode", "expenses", "exportedAt", "formatVersion"]
        let positions = try keys.map { try #require(json.range(of: "\"\($0)\" : ")?.lowerBound) }
        #expect(positions == positions.sorted())
    }

    @Test func repeatedExportImportCyclesDoNotShiftDates() throws {
        // Значение, на котором наивный ISO8601FormatStyle теряет 1 мс после первого цикла.
        let tricky = Date(timeIntervalSinceReferenceDate: 605_350_864.145_489_6)
        let record = BackupPayload.ExpenseRecord(
            id: UUID(), amountMinor: 100, date: tricky, note: "", categoryID: nil, createdAt: tricky, updatedAt: tricky
        )
        let payload = BackupPayload(exportedAt: tricky, currencyCode: "USD", categories: [], expenses: [record])

        let first = try BackupFormat.makeEncoder().encode(payload)
        var data = first
        for _ in 0..<5 {
            data = try BackupFormat.makeEncoder().encode(try BackupImporter.decode(data))
        }
        #expect(data == first)
        #expect(String(decoding: first, as: UTF8.self).contains("\"date\" : \"2020-03-08T09:01:04.145Z\""))
        #expect(try BackupImporter.decode(first) == payload)
    }

    @Test func importAcceptsIsoDatesWithoutFractionOrWithOffset() throws {
        let json = """
        {
          "formatVersion": 2, "exportedAt": "2026-10-08T12:00:00Z", "currencyCode": "EUR", "categories": [],
          "expenses": [{
            "id": "8E2A7C55-3D0B-4F0E-9C61-2B1A50F1D001", "amountMinor": 500, "note": "",
            "date": "2026-10-08T15:30:00.5+03:00", "createdAt": "2026-10-08T12:00:00Z", "updatedAt": "2026-10-08T12:00:00Z"
          }]
        }
        """
        let payload = try BackupImporter.decode(Data(json.utf8))
        let expense = try #require(payload.expenses.first)
        #expect(expense.date == BackupFormat.normalized(Date(timeIntervalSince1970: 1_791_462_600.5)))
        #expect(expense.categoryID == nil)
        #expect(payload.exportedAt == Date(timeIntervalSince1970: 1_791_460_800))
    }

    @Test func defaultFileNameUsesLocalCalendarDay() throws {
        let minsk = try #require(TimeZone(identifier: "Europe/Minsk"))
        // 2026-10-08 22:30 UTC — в Минске уже 9 октября.
        let date = Date(timeIntervalSince1970: 1_791_498_600)
        #expect(BackupExporter.defaultFileName(for: date, timeZone: minsk) == "Траты 2026-10-09")
        #expect(BackupExporter.defaultFileName(for: date, timeZone: .gmt) == "Траты 2026-10-08")
    }

    // MARK: - Формат 2: подкатегории

    @Test func subcategoriesSurviveExportAndImport() throws {
        let sourceContext = ModelContext(try BackupFixture.makeContainer())
        let seed = try BackupFixture.seed(sourceContext)
        let lunch = try BackupFixture.addSubcategory("Обеды", to: seed.food, in: sourceContext)
        seed.coffee.category = lunch
        try sourceContext.save()
        let data = try BackupExporter.exportData(from: sourceContext, currencyCode: "BYN", exportedAt: BackupFixture.exportedAt)

        let decoded = try BackupImporter.decode(data)
        #expect(decoded.convertedFromFormatVersion == nil)
        #expect(decoded.categories.first { $0.id == lunch.id }?.parentID == seed.food.id)

        let target = try BackupFixture.makeContainer()
        let report = try BackupImporter.apply(decoded, to: ModelContext(target), mode: .replace)
        #expect(report.categories == .init(added: 3))
        #expect(!report.isFromPreviousFormat)
        #expect(try BackupFixture.storedPayload(of: target) == decoded)
        let stored = try ModelContext(target).fetch(FetchDescriptor<ExpenseCategory>())
        let food = try #require(stored.first { $0.id == seed.food.id })
        #expect(food.children.map(\.id) == [lunch.id])

        // Повторная загрузка того же файла слиянием ничего не меняет.
        let again = try BackupImporter.apply(decoded, to: ModelContext(target), mode: .merge)
        #expect(again.categories == .init(unchanged: 3))
        #expect(again.expenses == .init(unchanged: 3))
        #expect(try BackupFixture.storedPayload(of: target) == decoded)
    }

    // MARK: - Формат 1

    /// Копия версии 1.0: цвета и иконки переводятся по migration.json, имена — нет, все категории верхнего уровня.
    @Test func version1FileIsConvertedToCurrentFormat() throws {
        let json = """
        {
          "formatVersion": 1, "exportedAt": "2026-10-08T12:00:00.000Z", "currencyCode": "BYN",
          "categories": [
            { "id": "1E2A7C55-3D0B-4F0E-9C61-2B1A50F1D001", "name": "Кафе и рестораны", "iconName": "fork.knife",
              "colorHex": "#DD6B20", "sortOrder": 0, "isArchived": false, "createdAt": "2026-01-01T10:00:00.000Z" },
            { "id": "1E2A7C55-3D0B-4F0E-9C61-2B1A50F1D002", "name": "Продукты", "iconName": "cart.fill",
              "colorHex": "#2E9D63", "sortOrder": 1, "isArchived": false, "createdAt": "2026-01-01T10:00:00.000Z" },
            { "id": "1E2A7C55-3D0B-4F0E-9C61-2B1A50F1D003", "name": "Хобби", "iconName": "star.fill",
              "colorHex": "#FFCC00", "sortOrder": 2, "isArchived": true, "createdAt": "2026-01-01T10:00:00.000Z" }
          ],
          "expenses": [
            { "id": "8E2A7C55-3D0B-4F0E-9C61-2B1A50F1D001", "amountMinor": 1250, "note": "Обед",
              "categoryID": "1E2A7C55-3D0B-4F0E-9C61-2B1A50F1D001", "date": "2026-10-08T12:00:00.000Z",
              "createdAt": "2026-10-08T12:00:00.000Z", "updatedAt": "2026-10-08T12:00:00.000Z" }
          ]
        }
        """

        let payload = try BackupImporter.decode(Data(json.utf8))

        #expect(payload.formatVersion == BackupFormat.currentVersion)
        #expect(payload.convertedFromFormatVersion == 1)
        #expect(payload.categories.map(\.name) == ["Кафе и рестораны", "Продукты", "Хобби"])
        #expect(payload.categories.map(\.colorHex) == [GouacheTone.abrikos, .shalfey, .okhra].map(\.mainHex))
        #expect(payload.categories.map(\.iconName) == ["fork-knife-fill", "basket-fill", "more-3-fill"])
        #expect(payload.categories.allSatisfy { $0.parentID == nil })
        #expect(payload.categories.last?.isArchived == true)

        let container = try BackupFixture.makeContainer()
        let report = try BackupImporter.apply(payload, to: ModelContext(container), mode: .replace)
        #expect(report.isFromPreviousFormat)
        #expect(report.categories == .init(added: 3))
        #expect(report.expenses == .init(added: 1))
        #expect(report.expensesWithMissingCategory == 0)

        // Экспорт после импорта — уже формат 2, повторный импорт его не переводит.
        let exported = try BackupExporter.exportData(
            from: ModelContext(container), currencyCode: "BYN", exportedAt: BackupFixture.exportedAt
        )
        let reread = try BackupImporter.decode(exported)
        #expect(reread.convertedFromFormatVersion == nil)
        #expect(reread.categories == (try BackupFixture.storedPayload(of: container)).categories)
        #expect(Set(reread.categories.map(\.iconName)) == Set(payload.categories.map(\.iconName)))
    }
}
