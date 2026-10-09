import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

@Suite struct SchemaTests {
    @Test func inMemoryContainerStoresExpenseWithCategory() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        let food = ExpenseCategory(name: "Еда", iconName: "cart", colorHex: "#34C759", sortOrder: 0)
        context.insert(food)
        context.insert(Expense(amountMinor: 1250, date: .now, category: food))
        try context.save()

        let expenses = try context.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1)
        #expect(expenses.first?.category?.name == "Еда")
        #expect(food.expenses.count == 1)
    }
}
