import Foundation
import SwiftData

/// Первая версия схемы хранилища. Модели вложены в схему, чтобы будущая миграция
/// (SchemaV2 + MigrationStage) не требовала переименований.
public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [ExpenseCategory.self, Expense.self]
    }

    @Model
    public final class ExpenseCategory {
        @Attribute(.unique) public var id: UUID
        public var name: String
        /// Имя SF Symbol.
        public var iconName: String
        /// Цвет в формате `#RRGGBB`.
        public var colorHex: String
        public var sortOrder: Int
        /// Архивная категория не предлагается при вводе, но остаётся в статистике.
        public var isArchived: Bool
        public var createdAt: Date

        @Relationship(deleteRule: .nullify, inverse: \Expense.category)
        public var expenses: [Expense] = []

        public init(
            id: UUID = UUID(),
            name: String,
            iconName: String,
            colorHex: String,
            sortOrder: Int,
            isArchived: Bool = false,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.iconName = iconName
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.createdAt = createdAt
        }
    }

    @Model
    public final class Expense {
        @Attribute(.unique) public var id: UUID
        /// Сумма в сотых долях валюты приложения (копейки/центы). Всегда > 0.
        public var amountMinor: Int64
        public var date: Date
        public var note: String
        public var category: ExpenseCategory?
        public var createdAt: Date
        public var updatedAt: Date

        public init(
            id: UUID = UUID(),
            amountMinor: Int64,
            date: Date,
            note: String = "",
            category: ExpenseCategory?,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.amountMinor = amountMinor
            self.date = date
            self.note = note
            self.category = category
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

public typealias ExpenseCategory = SchemaV1.ExpenseCategory
public typealias Expense = SchemaV1.Expense

/// План миграций. Новую версию схемы добавлять сюда вместе со стадией миграции.
public enum ExpenseMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
