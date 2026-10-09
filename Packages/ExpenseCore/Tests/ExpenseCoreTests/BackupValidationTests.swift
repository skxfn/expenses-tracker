import Foundation
import Testing
@testable import ExpenseCore

@Suite struct BackupValidationTests {
    private let categoryID = UUID()
    private let expenseID = UUID()

    private func category(id: UUID, parentID: UUID? = nil) -> BackupPayload.CategoryRecord {
        .init(
            id: id, name: "Еда", iconName: "cart", colorHex: "#34C759", sortOrder: 0, isArchived: false,
            createdAt: .now, parentID: parentID
        )
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

    private func unreadableReason(_ data: Data) throws -> BackupError.UnreadableReason? {
        let error = try #require(throws: BackupError.self) { try BackupImporter.decode(data) }
        guard case .unreadableFile(let reason) = error else {
            Issue.record("Ожидалась unreadableFile, получено \(error)")
            return nil
        }
        return reason
    }

    // MARK: - Битый файл

    @Test(arguments: ["", "не json", "{\"formatVersion\": 2,"])
    func notJSONIsUnreadable(text: String) throws {
        #expect(try unreadableReason(Data(text.utf8)) == .notJSON)
    }

    @Test func jsonOfAnotherShapeIsNotBackup() throws {
        #expect(try unreadableReason(Data("[1, 2]".utf8)) == .notBackup)
        #expect(try unreadableReason(Data("{}".utf8)) == .notBackup)
        #expect(try unreadableReason(Data(#"{"formatVersion": "2"}"#.utf8)) == .notBackup)
    }

    @Test func missingFieldIsReported() throws {
        let data = try corruptedFile { object in
            var expenses = object["expenses"] as! [[String: Any]]
            expenses[0]["amountMinor"] = nil
            object["expenses"] = expenses
        }
        #expect(try unreadableReason(data) == .missingField)

        let noCategories = try corruptedFile { $0["categories"] = nil }
        #expect(try unreadableReason(noCategories) == .missingField)
    }

    @Test func malformedValuesAreReported() throws {
        let badDate = try corruptedFile { object in
            var expenses = object["expenses"] as! [[String: Any]]
            expenses[0]["date"] = "вчера"
            object["expenses"] = expenses
        }
        #expect(try unreadableReason(badDate) == .badDate)

        let numericDate = try corruptedFile { $0["exportedAt"] = 12 }
        #expect(try unreadableReason(numericDate) == .badDate)

        let badID = try corruptedFile { object in
            var categories = object["categories"] as! [[String: Any]]
            categories[0]["id"] = "123"
            object["categories"] = categories
        }
        #expect(try unreadableReason(badID) == .badValue)

        let badAmount = try corruptedFile { object in
            var expenses = object["expenses"] as! [[String: Any]]
            expenses[0]["amountMinor"] = "сто"
            object["expenses"] = expenses
        }
        #expect(try unreadableReason(badAmount) == .badValue)
    }

    // MARK: - Версия формата

    @Test func newerFormatVersionAsksToUpdateApp() throws {
        // Структура новой версии может быть любой — важна только версия.
        let data = Data(#"{"formatVersion": 3, "records": []}"#.utf8)
        let error = try #require(throws: BackupError.self) { try BackupImporter.decode(data) }
        #expect(error == .newerFormat)
        #expect(error.errorDescription?.contains("Обновите приложение") == true)
    }

    @Test(arguments: [0, -1])
    func unknownOldFormatVersionIsRejected(version: Int) throws {
        let data = try corruptedFile { $0["formatVersion"] = version }
        #expect(throws: BackupError.unsupportedFormat) { try BackupImporter.decode(data) }
    }

    /// Payload прошлого формата, прочитанный в обход `decode` (без перевода), `apply` не принимает.
    @Test func validateRequiresCurrentVersion() throws {
        let data = try corruptedFile { $0["formatVersion"] = 1 }
        let raw = try BackupFormat.makeDecoder().decode(BackupPayload.self, from: data)
        #expect(throws: BackupError.unsupportedFormat) { try BackupImporter.validate(raw) }
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

    // MARK: - Иерархия

    @Test func validHierarchyIsAccepted() throws {
        let childID = UUID()
        // Подкатегория может идти в файле раньше родителя.
        let data = try encode(categories: [category(id: childID, parentID: categoryID), category(id: categoryID)], expenses: [])
        #expect(try BackupImporter.decode(data).categories.first?.parentID == categoryID)
    }

    @Test func parentMustExistInFile() throws {
        let childID = UUID()
        let data = try encode(categories: [category(id: categoryID), category(id: childID, parentID: UUID())], expenses: [])
        #expect(throws: BackupError.invalidParent(categoryID: childID)) { try BackupImporter.decode(data) }
    }

    @Test func categoryCannotBeItsOwnParent() throws {
        let data = try encode(categories: [category(id: categoryID, parentID: categoryID)], expenses: [])
        #expect(throws: BackupError.invalidParent(categoryID: categoryID)) { try BackupImporter.decode(data) }
    }

    @Test func hierarchyDepthIsAtMostOne() throws {
        let childID = UUID()
        let grandchildID = UUID()
        let data = try encode(categories: [
            category(id: categoryID),
            category(id: childID, parentID: categoryID),
            category(id: grandchildID, parentID: childID)
        ], expenses: [])
        #expect(throws: BackupError.invalidParent(categoryID: grandchildID)) { try BackupImporter.decode(data) }
    }

    // MARK: - Тексты

    /// Тексты — из copy.json, без UUID и номеров формата.
    @Test func everyErrorHasCopyTextWithoutIdentifiers() throws {
        let finals = try RepositoryFiles.copyFinals()
        let expected: [(BackupError, String)] = [
            (.unreadableFile(.notJSON), "error.backup.detail.notJSON"),
            (.unreadableFile(.notBackup), "error.backup.detail.notBackup"),
            (.unreadableFile(.missingField), "error.backup.detail.missingField"),
            (.unreadableFile(.badValue), "error.backup.detail.badValue"),
            (.unreadableFile(.badDate), "error.backup.detail.badDate"),
            (.invalidParent(categoryID: categoryID), "error.backup.detail.badValue"),
            (.newerFormat, "error.backup.newerFormat"),
            (.unsupportedFormat, "error.backup.unsupportedFormat"),
            (.duplicateCategoryID(categoryID), "error.backup.duplicateCategory"),
            (.duplicateExpenseID(expenseID), "error.backup.duplicateExpense"),
            (.nonPositiveAmount(expenseID: expenseID), "error.backup.nonPositiveAmount")
        ]
        for (error, copyID) in expected {
            let text = try #require(error.errorDescription)
            #expect(text == finals[copyID], "\(error)")
            #expect(text.range(of: "\\d", options: .regularExpression) == nil, "\(error)")
        }
        for reason in [BackupError.UnreadableReason.notJSON, .notBackup, .missingField, .badValue, .badDate] {
            #expect(finals["error.backup.detail.\(reason.rawValue)"] != nil)
        }
    }
}
