import SwiftData
import SwiftUI
import ExpenseCore

/// Корень приложения (INTEGRATION §6, §8 п. 5): вкладки со своим таб-баром, пуши внутри вкладок, общие шиты,
/// отложенное удаление с тостом и форматтер сумм в окружении.
///
/// Таб-бар — свой (`ShellTabBar`) в `safeAreaInset(edge: .bottom)` поверх `TabView` со скрытой системной панелью;
/// стоит в 30 от нижнего края экрана и прячется, пока во вкладке открыт пуш (настройки — без таб-бара, макет 12).
/// Корни вкладок без навигационной панели: шапки свои; заголовок вкладки нужен системной кнопке «‹ Траты».
struct ContentView: View {
    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @State private var router = AppRouter(tab: ContentView.initialTab)
    @State private var pendingDeletion = PendingDeletion()
    /// Стек пушей каждой вкладки.
    @State private var paths: [AppTab: [AppRoute]] = ContentView.initialPaths
    /// Нижний safe area экрана — чтобы поставить таб-бар на `tabbarBottom` от края.
    @State private var bottomSafeArea: CGFloat = 0
    @Namespace private var addTransition
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: $router.tab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.titleKey, systemImage: tab.systemImage, value: tab) {
                    stack(for: tab)
                        .toolbarVisibility(.hidden, for: .tabBar)
                }
            }
        }
        .deletionToast(pendingDeletion)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.bottom
        } action: { inset in
            bottomSafeArea = inset
        }
        .sheet(item: $router.sheet) { sheet in
            sheetContent(sheet)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { pendingDeletion.commitNow() }
        }
        .errorAlert($pendingDeletion.errorMessage)
        #if DEBUG
        .task { showDebugToastIfRequested() }
        #endif
        .environment(router)
        .environment(pendingDeletion)
        .environment(\.moneyFormatter, MoneyFormatter(currencyCode: currencyCode, locale: .app))
    }

    // MARK: - Таб-бар

    private var isTabBarVisible: Bool {
        paths[router.tab, default: []].isEmpty
    }

    private var tabBar: some View {
        Group {
            if isTabBarVisible {
                ShellTabBar(
                    selection: router.tab,
                    addTransition: addTransition,
                    onSelect: select,
                    onAdd: { router.presentAdd() }
                )
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Tokens.Spacing.tabbarBottom - bottomSafeArea)
                .transition(.opacity)
            }
        }
        .animation(Motion.exit, value: isTabBarVisible)
    }

    /// Тап по уже выбранной вкладке возвращает её к корню, как в системном таб-баре.
    private func select(_ tab: AppTab) {
        if tab == router.tab {
            paths[tab] = []
        } else {
            router.tab = tab
        }
    }

    // MARK: - Вкладки

    private func stack(for tab: AppTab) -> some View {
        NavigationStack(path: path(for: tab)) {
            root(for: tab)
                .navigationTitle(Text(tab.titleKey))
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(for: AppRoute.self) { route in
                    destination(route)
                }
        }
    }

    private func path(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { paths[tab, default: []] },
            set: { paths[tab] = $0 }
        )
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        #if DEBUG
        if let scenario = Self.periodScenario, tab != .calendar {
            PeriodDebugScreen(scenario: scenario, style: tab == .statistics ? .statistics : .home)
        } else {
            content(for: tab)
        }
        #else
        content(for: tab)
        #endif
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .expenses: HomeView()
        case .calendar: CalendarView()
        case .statistics: StatisticsView()
        }
    }

    @ViewBuilder
    private func destination(_ route: AppRoute) -> some View {
        switch route {
        case .settings: SettingsView()
        }
    }

    // MARK: - Шиты

    /// Новая трата из «+» (без даты) открывается зумом из круга; правка и запись на день — обычным шитом.
    @ViewBuilder
    private func sheetContent(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .expense(let mode):
            if case .add(date: nil) = mode {
                ExpenseSheet(mode: mode)
                    .navigationTransition(.zoom(sourceID: ShellTabBar.addTransitionID, in: addTransition))
            } else {
                ExpenseSheet(mode: mode)
            }
        }
    }

    // MARK: - Запуск

    private static var initialTab: AppTab {
        #if DEBUG
        DebugLaunchOptions.initialTab() ?? .expenses
        #else
        .expenses
        #endif
    }

    private static var initialPaths: [AppTab: [AppRoute]] {
        #if DEBUG
        DebugLaunchOptions.initialRoute().map { [.expenses: [$0]] } ?? [:]
        #else
        [:]
        #endif
    }

    #if DEBUG
    private static let periodScenario = DebugLaunchOptions.periodScenario()

    /// `-debugToast YES`: тост на паузе с несуществующим id — хранилище не меняется.
    private func showDebugToastIfRequested() {
        guard DebugLaunchOptions.showsDeletionToast() else { return }
        pendingDeletion.schedule(.init(id: UUID(), title: ""), store: ExpenseStore(context: modelContext))
        pendingDeletion.pause()
    }
    #endif
}
