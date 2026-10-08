import SwiftData
import SwiftUI
import ExpenseCore

/// Выбор валюты приложения: популярные сверху, остальные ниже, поиск по коду и названию.
struct CurrencyPickerView: View {
    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var pendingCode: String?

    var body: some View {
        let popular = CurrencyOption.popular.filter { $0.matches(searchText) }
        let other = CurrencyOption.other.filter { $0.matches(searchText) }
        List {
            if !popular.isEmpty {
                Section {
                    ForEach(popular) { row(for: $0) }
                } header: {
                    Text("Популярные")
                } footer: {
                    Text("Смена валюты меняет только обозначение: уже введённые суммы не пересчитываются.")
                }
            }
            if !other.isEmpty {
                Section("Все валюты") {
                    ForEach(other) { row(for: $0) }
                }
            }
        }
        .overlay {
            if popular.isEmpty && other.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Код или название")
        .navigationTitle("Валюта")
        .confirmationDialog(
            "Сменить валюту?",
            isPresented: Binding(get: { pendingCode != nil }, set: { if !$0 { pendingCode = nil } }),
            titleVisibility: .visible,
            presenting: pendingCode
        ) { code in
            Button("Сменить на \(code)") {
                currencyCode = code
            }
        } message: { code in
            Text("Уже введённые суммы не пересчитываются: 100 \(currencyCode) станут 100 \(code).")
        }
    }

    private func row(for option: CurrencyOption) -> some View {
        Button {
            select(option.code)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name)
                    Text(option.code)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if option.code == currencyCode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .tint(.primary)
        .accessibilityAddTraits(option.code == currencyCode ? .isSelected : [])
    }

    /// Если расходы уже есть — сначала предупреждаем, что суммы не пересчитаются.
    private func select(_ code: String) {
        guard code != currencyCode else { return }
        let expenseCount = (try? modelContext.fetchCount(FetchDescriptor<Expense>())) ?? 0
        if expenseCount > 0 {
            pendingCode = code
        } else {
            currencyCode = code
        }
    }
}

#Preview {
    NavigationStack {
        CurrencyPickerView()
    }
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
