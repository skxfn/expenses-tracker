import Foundation

/// Как загружать резервную копию в существующие данные.
public enum ImportMode: Sendable {
    /// Стереть все категории и расходы и загрузить данные из файла.
    case replace
    /// Записи с совпадающим `id` обновить данными из файла, новые добавить, ничего не удалять.
    case merge
}

/// Итог импорта.
public struct ImportReport: Equatable, Sendable {
    public struct Counts: Equatable, Sendable {
        public var added: Int
        public var updated: Int
        /// Пропущены: в базе уже точно такие же данные.
        public var unchanged: Int
        /// Удалены, потому что их нет в файле (только `.replace`).
        public var deleted: Int

        public init(added: Int = 0, updated: Int = 0, unchanged: Int = 0, deleted: Int = 0) {
            self.added = added
            self.updated = updated
            self.unchanged = unchanged
            self.deleted = deleted
        }
    }

    public var categories = Counts()
    public var expenses = Counts()
    /// Расходы, чья категория не нашлась ни в файле, ни (при `.merge`) в базе: загружены без категории.
    public var expensesWithMissingCategory = 0
    /// Валюта из файла. Применять ли её — решает UI.
    public let currencyCode: String

    init(currencyCode: String) {
        self.currencyCode = currencyCode
    }
}
