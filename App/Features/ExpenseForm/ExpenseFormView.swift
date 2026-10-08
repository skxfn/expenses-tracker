import SwiftData
import SwiftUI
import ExpenseCore

/// Форма добавления/редактирования расхода (показывается в sheet).
struct ExpenseFormView: View {
    @State private var model: ExpenseFormModel
    private let onSaved: () -> Void

    @Query(
        filter: #Predicate<ExpenseCategory> { !$0.isArchived },
        sort: [SortDescriptor(\ExpenseCategory.sortOrder), SortDescriptor(\ExpenseCategory.createdAt)]
    )
    private var activeCategories: [ExpenseCategory]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyFormatter) private var money
    @FocusState private var focusedField: Field?
    @State private var isConfirmingDelete = false

    /// - Parameter onSaved: вызывается после успешного сохранения (для haptic у родителя,
    ///   потому что сам sheet в этот момент закрывается).
    init(expense: Expense?, formatter: MoneyFormatter, onSaved: @escaping () -> Void) {
        _model = State(initialValue: ExpenseFormModel(expense: expense, formatter: formatter))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                amountSection
                categorySection
                Section {
                    DatePicker("Дата", selection: $model.date)
                    TextField("Заметка", text: $model.note, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focusedField, equals: .note)
                }
                if model.isEditing {
                    Section {
                        Button("Удалить расход", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(model.isEditing ? "Расход" : "Новый расход")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog("Удалить расход?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if model.delete(using: store) { dismiss() }
                }
            }
            .errorAlert($model.errorMessage)
            .onAppear {
                if !model.isEditing { focusedField = .amount }
            }
        }
    }

    private var amountSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                TextField("0", text: $model.amountText)
                    .keyboardType(.decimalPad)
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .focused($focusedField, equals: .amount)
                    .accessibilityLabel("Сумма")
                Text(money.currencySymbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Сумма")
        } footer: {
            if model.showsAmountHint {
                Text("Введите сумму больше нуля, не больше двух знаков после запятой.")
                    .foregroundStyle(.red)
            }
        }
    }

    private var categorySection: some View {
        Section {
            let categories = model.pickerCategories(active: activeCategories)
            if categories.isEmpty {
                Text("Активных категорий нет. Их можно добавить в «Настройки» → «Категории».")
                    .foregroundStyle(.secondary)
            } else {
                CategoryGridPicker(categories: categories, selectedID: model.category?.id) { category in
                    model.toggle(category)
                }
            }
        } header: {
            Text("Категория")
        } footer: {
            if model.category == nil {
                Text("Не выбрана — расход сохранится без категории.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Отмена") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Сохранить") {
                if model.save(using: store) {
                    onSaved()
                    dismiss()
                }
            }
            .disabled(!model.canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Готово") { focusedField = nil }
        }
    }

    private var store: ExpenseStore { ExpenseStore(context: modelContext) }

    private enum Field {
        case amount
        case note
    }
}

#Preview {
    ExpenseFormView(expense: nil, formatter: MoneyFormatter(currencyCode: "BYN")) {}
        .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
