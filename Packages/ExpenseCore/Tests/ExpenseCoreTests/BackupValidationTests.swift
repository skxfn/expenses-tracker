import Foundation
import Testing
@testable import ExpenseCore

@Suite struct BackupValidationTests {
    private let categoryID = UUID()
    private let expenseID = UUID()

    private func category(id: UUID) -> BackupPayload.CategoryRecord {
        .init(id: id, name: "Еда", iconName: "cart", colorHex: "#34C759", sortOrder: 0, isArchived: false, createdAt: .now)
    }

    private func expense(id: UUID, amount: Int64 = 100) -> BackupPayload.ExpenseRecord {
        .init(id: id, amountMinor: amount, date: .now, note: "", categoryID: categoryID, createdAt: .now, updatedAt: .now)
    }

    private func encode(categories: [BackupPayload.CategoryRecord], expenses: [BackupPayload.ExpenseRecord]) throws -> Data {
        let payload = BackupPayload(exportedAt: .now, currencyCode: "BYN", categories: categories, expenses: expenses)
        return try BackupFormat.makeEncoder().encode(payload)
    }

    /// Корректный файл, в котором `edit` портит JSON-объект верхнего уровня.
    private func corruptedFile(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        let valid = try encode(categories: [category(id: categoryID)], expenses: [expense(id: expenseID)])
        var object = try #require(try JSONSerialization.jsonObject(with: valid) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func unreadableDetails(_ data: Data) throws -> String {
        let error = try #require(throws: BackupError.self) { try BackupImporter.decode(data) }
        guard case .unreadableFile(let details) = error else {
            Issue.record("Ожидалась unreadableFile, получено \(error)")
            return ""
        }
        return details
    }

    // MARK: - Битый файл

    @Test(arguments: ["", "не json", "{\"formatVersion\": 1,"])
    func notJSONIsUnreadable(text: String) throws {
        #expect(try unreadableDetails(Data(text.utf8)) == "файл повреждён или это не JSON")
    }

    @Test func jsonOfAnotherShapeIsUnreadable() throws {
        #expect(try unreadableDetails(Data("[1, 2]".utf8)) == "это не резервная копия трат")
        #expect(try unreadableDetails(Data("{}".utf8)) == "нет поля «formatVersion»")
    }

    @Test func missingFieldIsNamedWithPath() throws {
        let data = try corruptedFile { object in
            var expenses = object["expenses"] as! [[String: Any]]
            expenses[0]["amountMinor"] = nil
            object["expenses"] = expenses
        }
        #expect(try unreadableDetails(data) == "нет поля «expenses[0].amountMinor»")
    }

    @Test func malformedValuesAreNamedWithPath() throws {
        let badDate = try corruptedFile { object in
            var expenses = object["expenses"] as! [[String: Any]]
            expenses[0]["date"] = "вчера"
            object["expenses"] = expenses
        }
        #expect(try unreadableDetails(badDate) == "неверное значение поля «expenses[0].date»")

        let badID = try corruptedFile { object in
            var categories = object["categories"] as! [[String: Any]]
            categories[0]["id"] = "123"
            object["categories"] = categories
        }
        #expect(try unreadableDetails(badID) == "неверное значение поля «categories[0].id»")

        let badAmount = try corruptedFile { object in
            var expenses = object["expenses"] as! [[String: Any]]
            expenses[0]["amountMinor"] = "сто"
            object["expenses"] = expenses
        }
        #expect(try unreadableDetails(badAmount) == "неверное значение поля «expenses[0].amountMinor»")
    }

    // MARK: - Версия формата

    @Test func newerFormatVersionAsksToUpdateApp() throws {
        // Структура новой версии может быть любой — важна только версия.
        let data = Data(#"{"formatVersion": 2, "records": []}"#.utf8)
        let error = try #require(throws: BackupError.self) { try BackupImporter.decode(data) }
        #expect(error == .unsupportedFormatVersion(2))
        #expect(error.errorDescription?.contains("Обновите приложение") == true)
    }

    @Test func unknownOldFormatVersionIsRejected() throws {
        let data = try corruptedFile { $0["formatVersion"] = 0 }
        #expect(throws: BackupError.unsupportedFormatVersion(0)) { try BackupImporter.decode(data) }
    }

    // MARK: - Содержимое

    @Test(arguments: [Int64(0), -5])
    func nonPositiveAmountIsRejected(amount: Int64) throws {
        let data = try encode(categories: [], expenses: [expense(id: UUID()), expense(id: expenseID, amount: amount)])
        #expect(throws: BackupError.nonPositiveAmount(expenseID: expenseID)) { try BackupImporter.decode(data) }
    }

    @Test func duplicateIDsAreRejected() throws {
        let categories = try encode(categories: [category(id: categoryID), category(id: categoryID)], expenses: [])
        #expect(throws: BackupError.duplicateCategoryID(categoryID)) { try BackupImporter.decode(categories) }

        let expenses = try encode(categories: [], expenses: [expense(id: expenseID), expense(id: expenseID)])
        #expect(throws: BackupError.duplicateExpenseID(expenseID)) { try BackupImporter.decode(expenses) }
    }

    @Test func missingCategoryReferenceIsNotAnError() throws {
        // Обработка такой ссылки — при применении (расход без категории), см. BackupImportTests.
        let data = try encode(categories: [], expenses: [expense(id: expenseID)])
        #expect(try BackupImporter.decode(data).expenses.first?.categoryID == categoryID)
    }

    @Test func everyErrorHasRussianDescription() {
        let errors: [BackupError] = [
            .unreadableFile(details: "нет поля «expenses»"),
            .unsupportedFormatVersion(2),
            .unsupportedFormatVersion(0),
            .duplicateCategoryID(categoryID),
            .duplicateExpenseID(expenseID),
            .nonPositiveAmount(expenseID: expenseID),
        ]
        for error in errors {
            #expect(error.localizedDescription.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil, "\(error)")
        }
    }
}
