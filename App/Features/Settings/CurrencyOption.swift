import Foundation
import ExpenseCore

/// Валюта в списке выбора: ISO-код, название и знак по-русски (интерфейс только на русском, `Locale.app`).
struct CurrencyOption: Identifiable, Hashable {
    let code: String
    /// «Белорусский рубль». Если система валюту не знает — сам код.
    let name: String

    var id: String { code }

    init(code: String, locale: Locale = .app) {
        self.code = code
        name = locale.localizedString(forCurrencyCode: code).map(RussianWords.capitalized) ?? code
    }

    static let popular = CurrencySettings.popularCodes.map { CurrencyOption(code: $0) }
    static let other = CurrencySettings.otherCodes.map { CurrencyOption(code: $0) }

    /// Знак в суммах: «Br», «$», «€» — как в форматтере сумм.
    var symbol: String {
        MoneyFormatter(currencyCode: code, locale: .app).currencySymbol
    }

    /// «Белорусский рубль · Br» — значение строки «Валюта» (`settings.currency.value`).
    var nameWithSymbol: String {
        L10n.format("settings.currency.value", name, symbol)
    }

    /// «Белорусский рубль · BYN» — в восстановлении копии виден код (`settings.currency.value`, `copy.json` → why).
    var nameWithCode: String {
        name == code ? code : L10n.format("settings.currency.value", name, code)
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty
            || code.localizedCaseInsensitiveContains(query)
            || name.localizedCaseInsensitiveContains(query)
    }
}
