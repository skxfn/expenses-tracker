import Foundation

/// Снимок расхода для статистики: чистое значение без SwiftData.
public struct ExpenseRecord: Sendable, Hashable, Identifiable {
    public let id: UUID
    /// Сумма в сотых долях валюты приложения. Всегда > 0.
    public let amountMinor: Int64
    public let date: Date
    /// Лист: категория или подкатегория. `nil` — трата без категории.
    public let categoryID: UUID?
    /// Категория верхнего уровня. Для траты в подкатегорию — её родитель,
    /// для траты прямо в категорию совпадает с `categoryID` («без подкатегории»).
    public let groupID: UUID?

    /// - Parameter groupID: категория верхнего уровня; `nil` — трата записана в категорию верхнего уровня
    ///   (`categoryID`) или без категории.
    public init(id: UUID = UUID(), amountMinor: Int64, date: Date, categoryID: UUID?, groupID: UUID? = nil) {
        self.id = id
        self.amountMinor = amountMinor
        self.date = date
        self.categoryID = categoryID
        self.groupID = groupID ?? categoryID
    }
}

extension ExpenseRecord {
    /// Единственное место, где статистика касается SwiftData-модели.
    /// Вызывать в том же контексте (акторе), которому принадлежит `expense`.
    public init(_ expense: Expense) {
        self.init(
            id: expense.id,
            amountMinor: expense.amountMinor,
            date: expense.date,
            categoryID: expense.category?.id,
            groupID: expense.category?.parent?.id ?? expense.category?.id
        )
    }
}

/// Фильтр расходов по категории.
public enum StatsCategoryFilter: Sendable, Hashable {
    /// Все расходы.
    case all
    /// Только траты, записанные ровно в эту категорию или подкатегорию (лист).
    /// Для категории с подкатегориями — только траты «без подкатегории».
    case category(UUID)
    /// Категория верхнего уровня вместе со всеми подкатегориями.
    case group(UUID)
    /// Только расходы без категории.
    case uncategorized

    func matches(_ record: ExpenseRecord) -> Bool {
        switch self {
        case .all: true
        case .category(let id): record.categoryID == id
        case .group(let id): record.groupID == id
        case .uncategorized: record.categoryID == nil
        }
    }
}
