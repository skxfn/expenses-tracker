import SwiftData

/// Перевод старых цветов, иконок и имён категорий на «Гуашь» и MingCute по `design/migration.json`.
/// Идемпотентно: таблицы старых и новых значений не пересекаются.
public enum LegacyCatalogMigration {
    public static func apply(in context: ModelContext) throws {
        // Реализация — по design/migration.json (этап «Данные и миграции»).
    }
}
