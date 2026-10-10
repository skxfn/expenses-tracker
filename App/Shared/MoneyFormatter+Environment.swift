import SwiftUI
import ExpenseCore

extension EnvironmentValues {
    /// Форматтер сумм в валюте приложения. В корне подставляется из `@AppStorage`,
    /// поэтому смена валюты сразу видна на всех экранах.
    @Entry var moneyFormatter = MoneyFormatter(currencyCode: CurrencySettings.fallbackCode, locale: .app)
}

extension Locale {
    /// Локаль чисел и дат приложения: интерфейс только на русском, регион устройства не влияет
    /// (иначе на нерусском регионе были бы «1,200.50» и чужие названия месяцев).
    static let app = Locale(identifier: "ru_RU")
}
