import Foundation
import SwiftData

/// Выгрузка всех категорий и расходов в JSON-файл резервной копии.
public enum BackupExporter {
    /// JSON резервной копии: pretty-printed, ключи по алфавиту, даты ISO 8601 (UTC, миллисекунды).
    public static func exportData(
        from context: ModelContext,
        currencyCode: String,
        exportedAt: Date = .now
    ) throws -> Data {
        try BackupFormat.makeEncoder().encode(makePayload(from: context, currencyCode: currencyCode, exportedAt: exportedAt))
    }

    /// Имя файла по умолчанию: `expenses-backup-YYYY-MM-DD.json` (дата по григорианскому календарю в `timeZone`).
    public static func defaultFileName(for date: Date = .now, timeZone: TimeZone = .current) -> String {
        let day = Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: timeZone).year().month().day()
        return "expenses-backup-\(date.formatted(day)).json"
    }

    /// Порядок записей стабильный, чтобы одинаковые данные давали одинаковый файл.
    static func makePayload(from context: ModelContext, currencyCode: String, exportedAt: Date) throws -> BackupPayload {
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        let expenses = try context.fetch(FetchDescriptor<Expense>(
            sortBy: [SortDescriptor(\.date), SortDescriptor(\.createdAt)]
        ))
        return BackupPayload(
            exportedAt: exportedAt,
            currencyCode: currencyCode,
            categories: categories.map { BackupPayload.CategoryRecord($0) },
            expenses: expenses.map { BackupPayload.ExpenseRecord($0) }
        )
    }
}
