import Foundation
import SwiftData

/// Чтение резервной копии и загрузка её в хранилище.
public enum BackupImporter {
    /// Читает и проверяет файл, хранилище не трогает: результат можно показать пользователю
    /// (дата, валюта, число записей) до выбора режима импорта.
    public static func decode(_ data: Data) throws(BackupError) -> BackupPayload {
        let decoder = BackupFormat.makeDecoder()
        // Версию читаем отдельно: файл новой версии может не совпадать по структуре с текущей.
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).formatVersion
        } catch {
            throw .unreadableFile(details: details(for: error))
        }
        guard version == BackupFormat.currentVersion else { throw .unsupportedFormatVersion(version) }

        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw .unreadableFile(details: details(for: error))
        }
        try validate(payload)
        return payload
    }

    /// Загружает payload в контекст и сохраняет. Всё или ничего: при любой ошибке изменения импорта
    /// откатываются. Несохранённые изменения контекста перед импортом сохраняются, чтобы откат их не стёр.
    @discardableResult
    public static func apply(_ payload: BackupPayload, to context: ModelContext, mode: ImportMode) throws -> ImportReport {
        try apply(payload, to: context, mode: mode, beforeCommit: {})
    }

    /// `beforeCommit` вызывается после всех изменений, перед сохранением, — точка для проверки отката в тестах.
    static func apply(
        _ payload: BackupPayload,
        to context: ModelContext,
        mode: ImportMode,
        beforeCommit: () throws -> Void
    ) throws -> ImportReport {
        try validate(payload)
        try context.save()

        var report = ImportReport(currencyCode: payload.currencyCode)
        do {
            // transaction сохраняет после блока, но при ошибке НЕ откатывает: изменения остаются в контексте.
            try context.transaction {
                report = try applyRecords(of: payload, mode: mode, in: context)
                try beforeCommit()
            }
        } catch {
            discardChanges(in: context)
            throw error
        }
        return report
    }

    static func validate(_ payload: BackupPayload) throws(BackupError) {
        guard payload.formatVersion == BackupFormat.currentVersion else {
            throw .unsupportedFormatVersion(payload.formatVersion)
        }
        var categoryIDs = Set<UUID>()
        for category in payload.categories where !categoryIDs.insert(category.id).inserted {
            throw .duplicateCategoryID(category.id)
        }
        var expenseIDs = Set<UUID>()
        for expense in payload.expenses {
            guard expenseIDs.insert(expense.id).inserted else { throw .duplicateExpenseID(expense.id) }
            guard expense.amountMinor > 0 else { throw .nonPositiveAmount(expenseID: expense.id) }
        }
    }
}

// MARK: - Применение записей

private extension BackupImporter {
    struct VersionProbe: Decodable {
        let formatVersion: Int
    }

    static func applyRecords(of payload: BackupPayload, mode: ImportMode, in context: ModelContext) throws -> ImportReport {
        var report = ImportReport(currencyCode: payload.currencyCode)
        let storedCategories = indexByID(try context.fetch(FetchDescriptor<ExpenseCategory>()), id: \.id)
        let storedExpenses = indexByID(try context.fetch(FetchDescriptor<Expense>()), id: \.id)

        var importedCategories: [UUID: ExpenseCategory] = [:]
        for record in payload.categories {
            importedCategories[record.id] = upsert(record, existing: storedCategories[record.id], in: context, counts: &report.categories)
        }

        // При замене категории не из файла будут удалены — ссылаться на них нельзя.
        let availableCategories = switch mode {
        case .merge: storedCategories.merging(importedCategories) { _, imported in imported }
        case .replace: importedCategories
        }
        for record in payload.expenses {
            let category = record.categoryID.flatMap { availableCategories[$0] }
            if record.categoryID != nil, category == nil {
                report.expensesWithMissingCategory += 1
            }
            upsert(record, category: category, existing: storedExpenses[record.id], in: context, counts: &report.expenses)
        }

        // Удаляем после перепривязки расходов: оставшиеся расходы уже не ссылаются на удаляемые категории.
        if mode == .replace {
            let fileExpenseIDs = Set(payload.expenses.map(\.id))
            for expense in storedExpenses.values where !fileExpenseIDs.contains(expense.id) {
                context.delete(expense)
                report.expenses.deleted += 1
            }
            for category in storedCategories.values where importedCategories[category.id] == nil {
                context.delete(category)
                report.categories.deleted += 1
            }
        }
        return report
    }

    static func upsert(
        _ record: BackupPayload.CategoryRecord,
        existing: ExpenseCategory?,
        in context: ModelContext,
        counts: inout ImportReport.Counts
    ) -> ExpenseCategory {
        guard let category = existing else {
            let category = ExpenseCategory(
                id: record.id,
                name: record.name,
                iconName: record.iconName,
                colorHex: record.colorHex,
                sortOrder: record.sortOrder,
                isArchived: record.isArchived,
                createdAt: record.createdAt
            )
            context.insert(category)
            counts.added += 1
            return category
        }
        if BackupPayload.CategoryRecord(category) == record {
            counts.unchanged += 1
        } else {
            category.name = record.name
            category.iconName = record.iconName
            category.colorHex = record.colorHex
            category.sortOrder = record.sortOrder
            category.isArchived = record.isArchived
            category.createdAt = record.createdAt
            counts.updated += 1
        }
        return category
    }

    static func upsert(
        _ record: BackupPayload.ExpenseRecord,
        category: ExpenseCategory?,
        existing: Expense?,
        in context: ModelContext,
        counts: inout ImportReport.Counts
    ) {
        guard let expense = existing else {
            let expense = Expense(
                id: record.id,
                amountMinor: record.amountMinor,
                date: record.date,
                note: record.note,
                category: nil,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
            // Связь — после insert: так новый объект уже принадлежит контексту категории.
            context.insert(expense)
            expense.category = category
            counts.added += 1
            return
        }
        var target = record
        target.categoryID = category?.id
        if BackupPayload.ExpenseRecord(expense) == target {
            counts.unchanged += 1
        } else {
            expense.amountMinor = record.amountMinor
            expense.date = record.date
            expense.note = record.note
            expense.category = category
            expense.createdAt = record.createdAt
            expense.updatedAt = record.updatedAt
            counts.updated += 1
        }
    }

    /// `rollback()` возвращает хранилище в исходное состояние, но уже загруженные объекты SwiftData
    /// держат устаревшие значения (и ссылки на откатанные вставки — обращение к ним роняет приложение),
    /// пока их не перечитать. Повторная выборка обновляет их.
    static func discardChanges(in context: ModelContext) {
        context.rollback()
        _ = try? context.fetch(FetchDescriptor<ExpenseCategory>())
        _ = try? context.fetch(FetchDescriptor<Expense>())
    }

    static func indexByID<Model>(_ models: [Model], id: (Model) -> UUID) -> [UUID: Model] {
        Dictionary(models.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Человекочитаемая причина ошибки декодирования, например «нет поля «expenses[2].date»».
    static func details(for error: any Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        switch error {
        case .keyNotFound(let key, let context):
            return "нет поля «\(path(context.codingPath + [key]))»"
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            return "файл повреждён или это не JSON"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return context.codingPath.isEmpty
                ? "это не резервная копия трат"
                : "неверное значение поля «\(path(context.codingPath))»"
        @unknown default:
            return error.localizedDescription
        }
    }

    static func path(_ codingPath: [any CodingKey]) -> String {
        let path = codingPath
            .map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }
            .joined()
        return String(path.trimmingPrefix("."))
    }
}
