import SwiftData
import SwiftUI
import ExpenseCore

@main
struct ExpensesApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                migrationPlan: ExpenseMigrationPlan.self
            )
        } catch {
            fatalError("Не удалось открыть хранилище: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
