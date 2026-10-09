import Foundation

/// Содержимое файла резервной копии.
///
/// Даты хранятся с точностью до миллисекунд: инициализаторы округляют их сами,
/// поэтому payload после записи в JSON и чтения обратно равен исходному.
public struct BackupPayload: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public var exportedAt: Date
    /// Код валюты приложения на момент экспорта.
    public var currencyCode: String
    public var categories: [CategoryRecord]
    public var expenses: [ExpenseRecord]
    /// Версия формата файла, если он старый и при чтении переведён в текущий (`import.v1`);
    /// `nil` — файл текущего формата. В файл не пишется.
    public internal(set) var convertedFromFormatVersion: Int?

    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, currencyCode, categories, expenses
    }

    public init(exportedAt: Date, currencyCode: String, categories: [CategoryRecord], expenses: [ExpenseRecord]) {
        self.formatVersion = BackupFormat.currentVersion
        self.exportedAt = BackupFormat.normalized(exportedAt)
        self.currencyCode = currencyCode
        self.categories = categories
        self.expenses = expenses
    }
}

extension BackupPayload {
    public struct CategoryRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var iconName: String
        public var colorHex: String
        public var sortOrder: Int
        public var isArchived: Bool
        public var createdAt: Date
        /// `nil` — категория верхнего уровня; иначе id родителя из этого же файла.
        public var parentID: UUID?

        public init(
            id: UUID,
            name: String,
            iconName: String,
            colorHex: String,
            sortOrder: Int,
            isArchived: Bool,
            createdAt: Date,
            parentID: UUID? = nil
        ) {
            self.id = id
            self.name = name
            self.iconName = iconName
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.createdAt = BackupFormat.normalized(createdAt)
            self.parentID = parentID
        }
    }

    public struct ExpenseRecord: Codable, Equatable, Sendable {
        public var id: UUID
        /// Сумма в сотых долях валюты, всегда > 0.
        public var amountMinor: Int64
        public var date: Date
        public var note: String
        /// `nil` — расход без категории.
        public var categoryID: UUID?
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID,
            amountMinor: Int64,
            date: Date,
            note: String,
            categoryID: UUID?,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.amountMinor = amountMinor
            self.date = BackupFormat.normalized(date)
            self.note = note
            self.categoryID = categoryID
            self.createdAt = BackupFormat.normalized(createdAt)
            self.updatedAt = BackupFormat.normalized(updatedAt)
        }
    }
}

// MARK: - Модель → запись

extension BackupPayload.CategoryRecord {
    init(_ category: ExpenseCategory) {
        self.init(
            id: category.id,
            name: category.name,
            iconName: category.iconName,
            colorHex: category.colorHex,
            sortOrder: category.sortOrder,
            isArchived: category.isArchived,
            createdAt: category.createdAt,
            parentID: category.parent?.id
        )
    }
}

extension BackupPayload.ExpenseRecord {
    init(_ expense: Expense) {
        self.init(
            id: expense.id,
            amountMinor: expense.amountMinor,
            date: expense.date,
            note: expense.note,
            categoryID: expense.category?.id,
            createdAt: expense.createdAt,
            updatedAt: expense.updatedAt
        )
    }
}
