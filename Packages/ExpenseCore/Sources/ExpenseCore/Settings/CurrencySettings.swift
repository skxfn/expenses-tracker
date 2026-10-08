import Foundation

/// Валюта приложения: одна на все суммы, хранится в UserDefaults.
public enum CurrencySettings {
    public static let fallbackCode = "BYN"

    /// Валюты, которые показываются в начале списка выбора.
    public static let popularCodes = ["BYN", "RUB", "USD", "EUR", "PLN", "UAH", "KZT", "GBP", "CNY", "GEL", "TRY"]

    /// Остальные распространённые ISO-коды по алфавиту, без популярных.
    public static let otherCodes = Locale.commonISOCurrencyCodes.filter { !popularCodes.contains($0) }.sorted()

    /// Валюта региона, если она известна, иначе `fallbackCode`.
    public static func defaultCode(for locale: Locale = .current) -> String {
        guard
            let code = locale.currency?.identifier,
            Locale.commonISOCurrencyCodes.contains(code)
        else { return fallbackCode }
        return code
    }

    /// Сохранённая валюта или валюта по умолчанию (без записи).
    public static func currencyCode(in defaults: UserDefaults, locale: Locale = .current) -> String {
        defaults.string(forKey: SettingsKeys.currencyCode) ?? defaultCode(for: locale)
    }

    /// Вызывать при запуске: фиксирует валюту по умолчанию, если её ещё нет.
    /// Иначе смена региона в iOS молча сменила бы валюту у всех старых сумм.
    @discardableResult
    public static func ensureCurrencyCode(in defaults: UserDefaults, locale: Locale = .current) -> String {
        if let stored = defaults.string(forKey: SettingsKeys.currencyCode) { return stored }
        let code = defaultCode(for: locale)
        defaults.set(code, forKey: SettingsKeys.currencyCode)
        return code
    }
}
