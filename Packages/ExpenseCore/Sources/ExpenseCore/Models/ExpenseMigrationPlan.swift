import SwiftData

/// План миграций. Новую версию схемы добавлять сюда вместе со стадией миграции.
public enum ExpenseMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }

    // Вычисляемое свойство: `static let` с не-Sendable `MigrationStage` в Swift 6 даёт ошибку изоляции.
    public static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: SchemaV1.self,
                toVersion: SchemaV2.self,
                willMigrate: nil,
                didMigrate: { context in try LegacyCatalogMigration.apply(in: context) }
            )
        ]
    }
}
