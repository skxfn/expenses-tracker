/// Обозначение белорусского рубля в суммах (`SettingsKeys.currencySymbolStyle`), выбирается в настройках
/// (design/INTEGRATION.md §3.3.1, строка «Обозначение»). Для других валют обозначение даёт ICU.
/// Для `@AppStorage`: значение хранится как `rawValue`.
public enum CurrencySymbolStyle: String, CaseIterable, Sendable {
    /// Знак U+20C5 (кириллическая «Б» с чертой).
    case sign
    /// ISO-код «BYN».
    case code

    public static let `default` = CurrencySymbolStyle.sign
}
