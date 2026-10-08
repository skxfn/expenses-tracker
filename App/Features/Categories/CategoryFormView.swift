import SwiftData
import SwiftUI
import ExpenseCore

/// Создание и редактирование категории (показывается в sheet).
struct CategoryFormView: View {
    @State private var model: CategoryFormModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moneyFormatter) private var money

    init(category: ExpenseCategory?) {
        _model = State(initialValue: CategoryFormModel(category: category))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Превью") {
                    CategoryAmountRow(appearance: model.appearance, subtitle: "Пример заметки", amount: money.string(fromMinor: 1250))
                }
                Section("Название") {
                    TextField("Например, «Кофе»", text: $model.name)
                }
                Section("Цвет") {
                    ColorSwatchPicker(selection: $model.colorHex)
                }
                ForEach(CategoryIconCatalog.groups) { group in
                    Section(group.title) {
                        IconGridPicker(symbols: group.symbols, colorHex: model.colorHex, selection: $model.iconName)
                    }
                }
                if model.isEditing {
                    manageSection
                }
            }
            .navigationTitle(model.isEditing ? "Категория" : "Новая категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if model.save(using: store) { dismiss() }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
        // На стеке, а не на форме: так алерт виден и с экрана удаления.
        .errorAlert($model.errorMessage)
    }

    private var manageSection: some View {
        Section {
            Button(model.isArchived ? "Вернуть из архива" : "Перенести в архив") {
                model.toggleArchive(using: store)
            }
            NavigationLink {
                DeleteCategoryView(model: model) { dismiss() }
            } label: {
                Text("Удалить категорию")
                    .foregroundStyle(.red)
            }
        } footer: {
            Text(model.isArchived
                 ? "Категория в архиве: не предлагается при вводе, но её траты остаются в статистике."
                 : "Архивная категория не предлагается при вводе, но её траты остаются в статистике.")
        }
    }

    private var store: ExpenseStore { ExpenseStore(context: modelContext) }
}

#Preview {
    CategoryFormView(category: nil)
        .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
