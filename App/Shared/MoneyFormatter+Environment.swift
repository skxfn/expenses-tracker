import SwiftUI
import ExpenseCore

extension EnvironmentValues {
    /// Форматтер сумм в валюте приложения. В корне подставляется из `@AppStorage`,
    /// поэтому смена валюты сразу видна на всех экранах.
    @Entry var moneyFormatter = MoneyFormatter(currencyCode: CurrencySettings.fallbackCode, locale: .app)
}

extension Locale {
    /// Локаль чисел и дат приложения — по языку интерфейса (`AppLanguage`): ru_RU или en_US.
    /// Регион устройства не влияет (иначе по-русски на регионе США были бы «1,200.50»).
    static let app = AppLanguage.current.locale
}
