import SwiftData

/// Создаёт контейнер SwiftData с актуальной схемой и планом миграций.
public enum ModelContainerFactory {
    /// - Parameter inMemory: `true` — хранилище только в памяти (тесты, превью).
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        // CloudKit не используется: `@Attribute(.unique)` с ним несовместим.
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: ExpenseMigrationPlan.self,
            configurations: configuration
        )
    }
}
