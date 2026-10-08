import SwiftData
import SwiftUI
import ExpenseCore

/// Что открыть в форме категории. `id` запоминается сразу — см. `ExpenseFormRoute`.
struct CategoryFormRoute: Identifiable {
    let id: String
    /// `nil` — новая категория.
    let category: ExpenseCategory?

    static let add = CategoryFormRoute(id: "add", category: nil)

    static func edit(_ category: ExpenseCategory) -> CategoryFormRoute {
        CategoryFormRoute(id: category.id.uuidString, category: category)
    }
}

/// Список категорий: активные с перестановкой, архивные отдельно.
struct CategoriesView: View {
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder), SortDescriptor(\ExpenseCategory.createdAt)])
    private var categories: [ExpenseCategory]

    @Environment(\.modelContext) private var modelContext
    @State private var formRoute: CategoryFormRoute?
    @State private var errorMessage: String?

    var body: some View {
        let active = categories.filter { !$0.isArchived }
        let archived = categories.filter(\.isArchived)
        List {
            if !active.isEmpty {
                Section {
                    ForEach(active) { row(for: $0) }
                        .onMove(perform: move)
                } header: {
                    Text("Активные")
                } footer: {
                    Text("В этом порядке категории показываются в форме расхода. Чтобы переставить — «Изменить».")
                }
            }
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { row(for: $0) }
                } header: {
                    Text("Архив")
                } footer: {
                    Text("Не предлагаются при вводе, но их траты остаются в статистике.")
                }
            }
        }
        .overlay {
            if categories.isEmpty {
                ContentUnavailableView {
                    Label("Категорий нет", systemImage: "square.grid.2x2")
                } description: {
                    Text("Расходы можно вводить и без категорий, но статистика с ними нагляднее.")
                } actions: {
                    Button("Добавить категорию") { formRoute = .add }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Категории")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    formRoute = .add
                } label: {
                    Label("Добавить категорию", systemImage: "plus")
                }
            }
            if !active.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(item: $formRoute) { route in
            CategoryFormView(category: route.category)
        }
        .errorAlert($errorMessage)
    }

    private func row(for category: ExpenseCategory) -> some View {
        Button {
            formRoute = .edit(category)
        } label: {
            HStack(spacing: 12) {
                CategoryIconView(CategoryAppearance(category))
                Text(category.name)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .tint(.primary)
    }

    private func move(from source: IndexSet, to destination: Int) {
        do {
            try ExpenseStore(context: modelContext).moveCategories(fromOffsets: source, toOffset: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CategoriesView()
    }
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
