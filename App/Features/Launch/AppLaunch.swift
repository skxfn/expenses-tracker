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
