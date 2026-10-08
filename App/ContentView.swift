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
    @State private var selectedTab = ContentView.initialTab

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ExpensesView()
            }
            .tabItem { Label("Расходы", systemImage: "list.bullet.rectangle") }
            .tag(AppTab.expenses)

            NavigationStack {
                StatisticsView()
            }
            .tabItem { Label("Статистика", systemImage: "chart.pie") }
            .tag(AppTab.statistics)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Настройки", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .environment(\.moneyFormatter, MoneyFormatter(currencyCode: currencyCode))
    }

    private static var initialTab: AppTab {
        #if DEBUG
        DebugLaunchOptions.initialTab() ?? .expenses
        #else
        .expenses
        #endif
    }
}
