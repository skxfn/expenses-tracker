import SwiftUI
import ExpenseCore

extension EnvironmentValues {
    /// Форматтер сумм в валюте приложения. В корне подставляется из `@AppStorage`,
    /// поэтому смена валюты сразу видна на всех экранах.
    @Entry var moneyFormatter = MoneyFormatter(currencyCode: CurrencySettings.fallbackCode)
}

extension MoneyFormatter {
    /// Символ валюты по правилам локали, например «Br» или «$».
    var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol
    }
}
