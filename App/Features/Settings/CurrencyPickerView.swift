import SwiftData
import SwiftUI
import ExpenseCore

/// Выбор валюты приложения (`currency.*`) в стиле настроек: популярные сверху, остальные ниже,
/// поиск по коду и названию. Суммы при смене не пересчитываются — об этом сноска и вопрос, если траты уже есть.
struct CurrencyPickerView: View {
    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var pendingCode: String?

    var body: some View {
        let popular = CurrencyOption.popular.filter { $0.matches(searchText) }
        let other = CurrencyOption.other.filter { $0.matches(searchText) }
        ScrollView {
            VStack(spacing: SettingsLayout.groupSpacing) {
                if !popular.isEmpty {
                    SettingsGroup(header: "currency.popular", footer: "currency.footer") {
                        ForEach(popular) { row(for: $0) }
                    }
                }
                if !other.isEmpty {
                    SettingsGroup(header: "currency.all") {
                        ForEach(other) { row(for: $0) }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .overlay {
            if popular.isEmpty && other.isEmpty {
                // `currency.searchEmpty`: текст даёт система.
                ContentUnavailableView.search(text: searchText)
            }
        }
        .background(Theme.canvas)
        .navigationTitle("currency.title")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: Text("currency.search"))
        .confirmationDialog(
            "currency.confirm",
            isPresented: Binding(get: { pendingCode != nil }, set: { if !$0 { pendingCode = nil } }),
            titleVisibility: .visible,
            presenting: pendingCode
        ) { code in
            Button(L10n.format("currency.confirmButton", code)) {
                currencyCode = code
            }
        } message: { code in
            Text(verbatim: L10n.format("currency.confirmMessage", currencyCode, code))
        }
    }

    private func row(for option: CurrencyOption) -> some View {
        let isSelected = option.code == currencyCode
        return Button {
            select(option.code)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: option.name)
                        .typeStyle(.body)
                        .foregroundStyle(Theme.ink)
                    Text(verbatim: option.code)
                        .typeStyle(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                if isSelected {
                    Image(systemName: "checkmark")
                        .typeStyle(.headline)
                        .foregroundStyle(Theme.ink)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(minHeight: SettingsLayout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Если траты уже есть — сначала предупреждаем, что суммы не пересчитаются.
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

#if DEBUG
#Preview {
    NavigationStack {
        CurrencyPickerView()
    }
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
#endif
