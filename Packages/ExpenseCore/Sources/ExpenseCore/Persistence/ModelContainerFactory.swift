import Foundation
import SwiftData

/// Создаёт контейнер SwiftData с актуальной схемой и планом миграций.
public enum ModelContainerFactory {
    /// - Parameter inMemory: `true` — хранилище только в памяти (тесты, превью).
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        // CloudKit не используется: `@Attribute(.unique)` с ним несовместим.
        try make(ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none))
    }

    /// Хранилище в указанном файле (тест миграции на копии базы).
    public static func make(storeURL: URL) throws -> ModelContainer {
        try make(ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none))
    }

    private static var schema: Schema { Schema(versionedSchema: SchemaV2.self) }

    /// Core Data падает (SIGSEGV в `-[NSSQLEntity_DerivedAttributesExtension _generateTriggerSQL]`),
    /// если хранилища одной схемы открываются одновременно из разных потоков. В приложении контейнер
    /// один; лок нужен параллельным тестам и превью.
    private static let creationLock = NSLock()

    private static func make(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try creationLock.withLock {
            try ModelContainer(for: schema, migrationPlan: ExpenseMigrationPlan.self, configurations: configuration)
        }
    }
}
