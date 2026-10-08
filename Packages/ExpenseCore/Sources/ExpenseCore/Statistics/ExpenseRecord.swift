import Foundation

/// Снимок расхода для статистики: чистое значение без SwiftData.
public struct ExpenseRecord: Sendable, Hashable, Identifiable {
    public let id: UUID
    /// Сумма в сотых долях валюты приложения. Всегда > 0.
    public let amountMinor: Int64
    public let date: Date
    /// `nil` — расход без категории.
    public let categoryID: UUID?

    public init(id: UUID = UUID(), amountMinor: Int64, date: Date, categoryID: UUID?) {
        self.id = id
        self.amountMinor = amountMinor
        self.date = date
        self.categoryID = categoryID
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
            categoryID: expense.category?.id
        )
    }
}

/// Фильтр расходов по категории.
public enum StatsCategoryFilter: Sendable, Hashable {
    /// Все расходы.
    case all
    /// Только расходы указанной категории.
    case category(UUID)
    /// Только расходы без категории.
    case uncategorized

    func matches(_ record: ExpenseRecord) -> Bool {
        switch self {
        case .all: true
        case .category(let id): record.categoryID == id
        case .uncategorized: record.categoryID == nil
        }
    }
}
