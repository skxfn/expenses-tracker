import Foundation
import SwiftData

/// Чтение резервной копии и загрузка её в хранилище.
public enum BackupImporter {
    /// Читает и проверяет файл, хранилище не трогает: результат можно показать пользователю
    /// (дата, валюта, число записей) до выбора режима импорта.
    /// Файл формата 1 переводится в текущий (`convertedFromFormatVersion`): все категории — верхнего
    /// уровня, цвета и иконки — по таблицам `design/migration.json`, имена не меняются.
    public static func decode(_ data: Data) throws(BackupError) -> BackupPayload {
        let decoder = BackupFormat.makeDecoder()
        // Версию читаем отдельно: файл новой версии может не совпадать по структуре с текущей.
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).formatVersion
        } catch {
            // Без `formatVersion` (или с ним не того типа) — JSON, но не наш файл.
            throw .unreadableFile(reason(for: error) == .notJSON ? .notJSON : .notBackup)
        }
        try checkVersion(version)

        var payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw .unreadableFile(reason(for: error))
        }
        if version < BackupFormat.currentVersion {
            payload = convertedFromVersion1(payload)
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

    /// Payload текущего формата без дублей id, нулевых сумм и с иерархией глубины не больше 1:
    /// родитель подкатегории есть в файле, это не она сама и он верхнего уровня.
    static func validate(_ payload: BackupPayload) throws(BackupError) {
        try checkVersion(payload.formatVersion)
        guard payload.formatVersion == BackupFormat.currentVersion else { throw .unsupportedFormat }

        var categoriesByID: [UUID: BackupPayload.CategoryRecord] = [:]
        for category in payload.categories {
            guard categoriesByID.updateValue(category, forKey: category.id) == nil else {
                throw .duplicateCategoryID(category.id)
            }
        }
        for category in payload.categories {
            guard let parentID = category.parentID else { continue }
            guard parentID != category.id, let parent = categoriesByID[parentID], parent.parentID == nil else {
                throw .invalidParent(categoryID: category.id)
            }
        }
        var expenseIDs = Set<UUID>()
        for expense in payload.expenses {
            guard expenseIDs.insert(expense.id).inserted else { throw .duplicateExpenseID(expense.id) }
            guard expense.amountMinor > 0 else { throw .nonPositiveAmount(expenseID: expense.id) }
            // Больше предела одной траты — иначе итоги статистики переполнят `Int64` и приложение упадёт.
            guard expense.amountMinor <= Money.maxAmountMinor else { throw .unreadableFile(.badValue) }
        }
    }

    /// Формат 1 → текущий: все категории верхнего уровня, цвета и иконки — по таблицам
    /// `design/migration.json` (как при миграции хранилища V1 → V2), имена не меняются.
    static func convertedFromVersion1(_ payload: BackupPayload) -> BackupPayload {
        let categories = payload.categories.map { record in
            var record = record
            record.parentID = nil
            record.colorHex = LegacyCatalogMigration.colorHex(forLegacy: record.colorHex)
            record.iconName = LegacyCatalogMigration.iconName(forLegacy: record.iconName, categoryName: record.name)
            return record
        }
        var converted = BackupPayload(
            exportedAt: payload.exportedAt,
            currencyCode: payload.currencyCode,
            categories: categories,
            expenses: payload.expenses
        )
        converted.convertedFromFormatVersion = payload.formatVersion
        return converted
    }
}

// MARK: - Применение записей

private extension BackupImporter {
    struct VersionProbe: Decodable {
        let formatVersion: Int
    }

    /// Новее текущей — `newerFormat`, старше первой — `unsupportedFormat`.
    static func checkVersion(_ version: Int) throws(BackupError) {
        guard version <= BackupFormat.currentVersion else { throw .newerFormat }
        guard version >= BackupFormat.oldestReadableVersion else { throw .unsupportedFormat }
    }

    static func applyRecords(of payload: BackupPayload, mode: ImportMode, in context: ModelContext) throws -> ImportReport {
        var report = ImportReport(currencyCode: payload.currencyCode)
        report.isFromPreviousFormat = payload.convertedFromFormatVersion != nil
        let storedCategories = indexByID(try context.fetch(FetchDescriptor<ExpenseCategory>()), id: \.id)
        let storedExpenses = indexByID(try context.fetch(FetchDescriptor<Expense>()), id: \.id)

        // Два прохода: сначала категории верхнего уровня, затем подкатегории — их родитель уже загружен.
        var importedCategories: [UUID: ExpenseCategory] = [:]
        let topLevelFirst = payload.categories.filter { $0.parentID == nil } + payload.categories.filter { $0.parentID != nil }
        for record in topLevelFirst {
            // Родитель проверен в validate: он есть в файле и идёт в первом проходе.
            let parent = record.parentID.flatMap { importedCategories[$0] }
            importedCategories[record.id] = upsert(
                record, parent: parent, existing: storedCategories[record.id], in: context, counts: &report.categories
            )
        }
        // Категория из файла стала подкатегорией, а в базе у неё остались свои подкатегории, которых
        // нет в файле (только при слиянии): глубина была бы 2 — такие переходят к её родителю.
        for category in importedCategories.values {
            guard let parent = category.parent else { continue }
            for child in Array(category.children) {
                child.parent = parent
            }
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
        parent: ExpenseCategory?,
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
            // Связь — после insert: так новый объект уже принадлежит контексту родителя.
            context.insert(category)
            category.parent = parent
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
            category.parent = parent
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

    /// Причина ошибки декодирования для `error.backup.detail.*`.
    static func reason(for error: any Error) -> BackupError.UnreadableReason {
        guard let error = error as? DecodingError else { return .notJSON }
        switch error {
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            return .notJSON
        case .keyNotFound:
            return .missingField
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            guard let key = context.codingPath.last else { return .notBackup }
            return BackupFormat.dateKeys.contains(key.stringValue) ? .badDate : .badValue
        @unknown default:
            return .badValue
        }
    }
}
