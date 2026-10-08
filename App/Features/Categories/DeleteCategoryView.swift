import SwiftData
import SwiftUI
import ExpenseCore

/// Удаление категории с выбором, куда деть её расходы.
/// Ошибки показывает `CategoryFormView`: алерт висит на её `NavigationStack`.
struct DeleteCategoryView: View {
    let model: CategoryFormModel
    let onDeleted: () -> Void

    @Query(
        filter: #Predicate<ExpenseCategory> { !$0.isArchived },
        sort: [SortDescriptor(\ExpenseCategory.sortOrder), SortDescriptor(\ExpenseCategory.createdAt)]
    )
    private var activeCategories: [ExpenseCategory]

    @Environment(\.modelContext) private var modelContext
    /// `nil` — оставить расходы без категории.
    @State private var targetID: UUID?
    @State private var isConfirming = false

    var body: some View {
        Form {
            if model.expenseCount > 0 {
                Section {
                    Picker("Куда перенести расходы", selection: $targetID) {
                        Text("Оставить без категории").tag(UUID?.none)
                        ForEach(targets) { category in
                            Label {
                                Text(category.name)
                            } icon: {
                                CategoryIconView(CategoryAppearance(category), diameter: 28)
                            }
                            .tag(UUID?.some(category.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Расходов в категории: \(model.expenseCount)")
                } footer: {
                    Text("Выберите категорию, куда перенести эти расходы, или оставьте их без категории.")
                }
            } else {
                Section {
                    Text("В категории нет расходов.")
                }
            }

            Section {
                Button("Удалить категорию", role: .destructive) {
                    isConfirming = true
                }
            }
        }
        .navigationTitle("Удаление")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Удалить категорию «\(model.name)»?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                let target = targets.first { $0.id == targetID }
                if model.delete(using: ExpenseStore(context: modelContext), reassignTo: target) {
                    onDeleted()
                }
            }
        } message: {
            Text("Отменить это нельзя.")
        }
    }

    /// Куда можно перенести расходы: активные категории, кроме удаляемой.
    private var targets: [ExpenseCategory] {
        activeCategories.filter { $0.id != model.categoryID }
    }
}
