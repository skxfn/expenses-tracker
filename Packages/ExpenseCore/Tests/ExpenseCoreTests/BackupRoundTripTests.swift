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
        try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: ExpenseMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
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
        #expect(json.contains("\"formatVersion\" : 1"))
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
          "formatVersion": 1, "exportedAt": "2026-10-08T12:00:00Z", "currencyCode": "EUR", "categories": [],
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
        #expect(BackupExporter.defaultFileName(for: date, timeZone: minsk) == "expenses-backup-2026-10-09.json")
        #expect(BackupExporter.defaultFileName(for: date, timeZone: .gmt) == "expenses-backup-2026-10-08.json")
    }
}
