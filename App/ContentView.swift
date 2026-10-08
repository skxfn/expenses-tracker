import SwiftUI
import ExpenseCore

enum AppTab: String {
    case expenses
    case statistics
    case settings
}

/// Корень приложения: вкладки и форматтер сумм в окружении.
struct ContentView: View {
    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @State private var selectedTab = AppTab.expenses

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ExpensesView()
            }
            .tabItem { Label("Расходы", systemImage: "list.bullet.rectangle") }
            .tag(AppTab.expenses)
        }
        .environment(\.moneyFormatter, MoneyFormatter(currencyCode: currencyCode))
    }
}
