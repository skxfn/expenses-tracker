import SwiftUI
import ExpenseCore

/// Корень приложения: вкладки, общие шиты, отложенное удаление и форматтер сумм в окружении.
/// Внешний вид таб-бара с «+» — этап «Оболочка».
struct ContentView: View {
    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @State private var router = AppRouter(tab: ContentView.initialTab)
    @State private var pendingDeletion = PendingDeletion()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("tabbar.expenses", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.expenses)

            NavigationStack { CalendarView() }
                .tabItem { Label("tabbar.calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)

            NavigationStack { StatisticsView() }
                .tabItem { Label("tabbar.statistics", systemImage: "chart.pie") }
                .tag(AppTab.statistics)
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .expense(let mode): ExpenseSheet(mode: mode)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { pendingDeletion.commitNow() }
        }
        .environment(router)
        .environment(pendingDeletion)
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
