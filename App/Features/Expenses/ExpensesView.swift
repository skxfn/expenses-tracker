import SwiftData
import SwiftUI
import ExpenseCore

/// Что открыть в форме расхода. `id` запоминается сразу: после удаления расхода
/// SwiftUI ещё обращается к маршруту, а читать свойства удалённой модели небезопасно.
struct ExpenseFormRoute: Identifiable {
    let id: String
    /// `nil` — новый расход.
    let expense: Expense?

    static let add = ExpenseFormRoute(id: "add", expense: nil)

    static func edit(_ expense: Expense) -> ExpenseFormRoute {
        ExpenseFormRoute(id: expense.id.uuidString, expense: expense)
    }
}

/// Вкладка «Расходы»: итог месяца, список по дням, быстрое добавление.
struct ExpensesView: View {
    @Query(sort: [
        SortDescriptor(\Expense.date, order: .reverse),
        SortDescriptor(\Expense.createdAt, order: .reverse)
    ])
    private var expenses: [Expense]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var money
    @State private var formRoute: ExpenseFormRoute?
    @State private var savedCount = 0
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if expenses.isEmpty {
                emptyState
            } else {
                list(ExpensesListContent(expenses: expenses))
            }
        }
        .navigationTitle("Расходы")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    formRoute = .add
                } label: {
                    Label("Добавить расход", systemImage: "plus")
                }
            }
        }
        .sheet(item: $formRoute) { route in
            ExpenseFormView(expense: route.expense, formatter: money) {
                savedCount += 1
            }
        }
        .sensoryFeedback(.success, trigger: savedCount)
        .errorAlert($errorMessage)
    }

    private func list(_ content: ExpensesListContent) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.monthTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(money.string(fromMinor: content.monthTotalMinor))
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            ForEach(content.sections) { section in
                Section {
                    ForEach(section.expenses) { expense in
                        Button {
                            formRoute = .edit(expense)
                        } label: {
                            ExpenseRowView(
                                appearance: CategoryAppearance(expense.category),
                                note: expense.note,
                                amount: money.string(fromMinor: expense.amountMinor)
                            )
                        }
                        .tint(.primary)
                        .swipeActions {
                            Button("Удалить", systemImage: "trash", role: .destructive) {
                                delete(expense)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(section.title)
                        Spacer()
                        Text(money.string(fromMinor: section.totalMinor))
                            .monospacedDigit()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            addButton
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Пока нет трат", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Добавьте первый расход — он появится здесь, а на вкладке «Статистика» будут графики.")
        } actions: {
            Button("Добавить расход") {
                formRoute = .add
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var addButton: some View {
        Button {
            formRoute = .add
        } label: {
            Label("Добавить расход", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func delete(_ expense: Expense) {
        do {
            try ExpenseStore(context: modelContext).deleteExpense(expense)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ExpensesView()
    }
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
