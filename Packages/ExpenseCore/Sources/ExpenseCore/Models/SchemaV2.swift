import Foundation
import SwiftData

/// Вторая версия схемы: двухуровневые категории (категория → подкатегории).
/// Глубина — один уровень; трата может ссылаться на категорию любого уровня.
public enum SchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [ExpenseCategory.self, Expense.self]
    }

    @Model
    public final class ExpenseCategory {
        @Attribute(.unique) public var id: UUID
        public var name: String
        /// Имя иконки MingCute (имя ассета).
        public var iconName: String
        /// Основной светлый тон «Гуаши» `#RRGGBB`. У подкатегории совпадает с родителем, UI его не читает.
        public var colorHex: String
        public var sortOrder: Int
        /// Архивная категория не предлагается при вводе, но остаётся в статистике.
        public var isArchived: Bool
        public var createdAt: Date
        /// `nil` — категория верхнего уровня.
        public var parent: ExpenseCategory?

        @Relationship(deleteRule: .cascade, inverse: \ExpenseCategory.parent)
        public var children: [ExpenseCategory] = []

        @Relationship(deleteRule: .nullify, inverse: \Expense.category)
        public var expenses: [Expense] = []

        public init(
            id: UUID = UUID(),
            name: String,
            iconName: String,
            colorHex: String,
            sortOrder: Int,
            isArchived: Bool = false,
            createdAt: Date = .now,
            parent: ExpenseCategory? = nil
        ) {
            self.id = id
            self.name = name
            self.iconName = iconName
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.createdAt = createdAt
            self.parent = parent
        }
    }

    @Model
    public final class Expense {
        @Attribute(.unique) public var id: UUID
        /// Сумма в сотых долях валюты приложения (копейки/центы). Всегда > 0.
        public var amountMinor: Int64
        public var date: Date
        public var note: String
        /// Категория или подкатегория.
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

public typealias ExpenseCategory = SchemaV2.ExpenseCategory
public typealias Expense = SchemaV2.Expense
