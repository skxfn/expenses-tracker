import Foundation
import SwiftData
import ExpenseCore

/// Подготовка при запуске: валюта, хранилище, базовые категории.
enum AppLaunch {
    enum State {
        case ready(ModelContainer)
        /// Хранилище не открылось. Данные не трогаем — только показываем причину.
        case failed(StoreFailure)
    }

    static func prepare(defaults: UserDefaults = .standard) -> State {
        // До показа любых сумм: иначе смена региона в iOS молча сменила бы валюту.
        CurrencySettings.ensureCurrencyCode(in: defaults)

        let container: ModelContainer
        do {
            container = try ModelContainerFactory.make()
        } catch {
            return .failed(StoreFailure(error))
        }

        // Перевод старых цветов, иконок и имён — ещё раз при каждом запуске (идемпотентно, быстро):
        // если `didMigrate` стадии V1→V2 упал, SwiftData уже перевела базу на V2 и стадию не повторит.
        try? LegacyCatalogMigration.apply(in: container.mainContext)

        // Без базовых категорий приложение работает; флаг при ошибке не ставится,
        // поэтому попытка повторится при следующем запуске.
        try? ExpenseStore(context: container.mainContext).seedDefaultCategoriesIfNeeded(defaults: defaults)

        #if DEBUG
        DebugLaunchOptions.applyDemoDataIfRequested(to: container.mainContext, defaults: defaults)
        #endif
        return .ready(container)
    }
}

/// Описание ошибки открытия хранилища для экрана ошибки.
struct StoreFailure {
    let summary: String
    let details: String

    init(_ error: any Error) {
        summary = error.localizedDescription
        details = String(reflecting: error)
    }
}

#if DEBUG
/// Аргументы запуска для отладки и скриншотов (читаются из `UserDefaults`, куда iOS кладёт `-ключ значение`):
/// `-demoData YES` — заполнить демо-тратами, если расходов ещё нет;
/// `-debugTab expenses|calendar|statistics` — открыть вкладку;
/// `-debugRoute settings` — сразу открыть пуш на вкладке «Траты» (настройки);
/// `-debugPeriod YES|day|week|year|range|past|sheet` — вместо содержимого «Трат» и «Статистики» экран проверки
/// шапки периода (`PeriodDebugScreen`, сценарии — `PeriodDebugScenario`);
/// `-debugToast YES` — тост удаления на паузе (ничего не удаляет);
/// `-debugAdd YES` — открыть шит новой траты, как по «+» (зум из круга).
enum DebugLaunchOptions {
    static func applyDemoDataIfRequested(to context: ModelContext, defaults: UserDefaults) {
        guard
            defaults.bool(forKey: "demoData"),
            (try? context.fetchCount(FetchDescriptor<Expense>())) == 0
        else { return }
        try? DemoData.fill(context: context, currencyCode: CurrencySettings.currencyCode(in: defaults))
    }

    static func initialTab(defaults: UserDefaults = .standard) -> AppTab? {
        defaults.string(forKey: "debugTab").flatMap(AppTab.init(rawValue:))
    }

    static func initialRoute(defaults: UserDefaults = .standard) -> AppRoute? {
        defaults.string(forKey: "debugRoute") == "settings" ? .settings : nil
    }

    static func periodScenario(defaults: UserDefaults = .standard) -> PeriodDebugScenario? {
        guard let value = defaults.string(forKey: "debugPeriod") else { return nil }
        return PeriodDebugScenario(rawValue: value) ?? (defaults.bool(forKey: "debugPeriod") ? .month : nil)
    }

    static func showsDeletionToast(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "debugToast")
    }

    static func presentsAddSheet(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "debugAdd")
    }
}
#endif
