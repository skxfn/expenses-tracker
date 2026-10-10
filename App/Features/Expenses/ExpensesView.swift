import SwiftData
import SwiftUI
import ExpenseCore

/// Вкладка «Расходы»: итог месяца, список по дням, быстрое добавление.
struct ExpensesView: View {
    @Query(sort: [
        SortDescriptor(\Expense.date, order: .reverse),
        SortDescriptor(\Expense.createdAt, order: .reverse)
    ])
    private var expenses: [Expense]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var money
    @Environment(AppRouter.self) private var router
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
                    router.presentAdd()
                } label: {
                    Label("Добавить расход", systemImage: "plus")
                }
            }
        }
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
                            router.presentEdit(expenseID: expense.id)
                        } label: {
                            CategoryAmountRow(
                                appearance: CategoryAppearance(expense.category),
                                subtitle: expense.note,
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
                router.presentAdd()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var addButton: some View {
        Button {
            router.presentAdd()
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
    .environment(AppRouter())
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
