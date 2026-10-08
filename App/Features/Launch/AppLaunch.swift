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
/// `-demoData YES` — заполнить демо-тратами, если расходов ещё нет; `-debugTab statistics` — открыть вкладку.
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
}
#endif
