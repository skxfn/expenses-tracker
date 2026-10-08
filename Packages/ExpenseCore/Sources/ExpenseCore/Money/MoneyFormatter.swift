import Foundation

/// Форматирование сумм из minor-единиц. Копейки показываются, только если они есть:
/// `120000` → «1 200 Br», `1250` → «12,50 Br».
public struct MoneyFormatter: Sendable {
    public let currencyCode: String
    public let locale: Locale

    public init(currencyCode: String, locale: Locale = .autoupdatingCurrent) {
        self.currencyCode = currencyCode
        self.locale = locale
    }

    /// Сумма с символом валюты по правилам локали.
    public func string(fromMinor minor: Int64) -> String {
        Money.major(fromMinor: minor).formatted(
            .currency(code: currencyCode)
                .locale(locale)
                .precision(.fractionLength(fractionLength(for: minor)))
        )
    }

    /// Сумма без валюты и разделителей разрядов — для поля ввода при редактировании:
    /// `1250` → «12,50», `120000` → «1200». Обратно разбирается `Money.minor(fromInput:)`.
    public func editingString(fromMinor minor: Int64) -> String {
        Money.major(fromMinor: minor).formatted(
            .number
                .locale(locale)
                .grouping(.never)
                .precision(.fractionLength(fractionLength(for: minor)))
        )
    }

    private func fractionLength(for minor: Int64) -> Int {
        minor % Money.minorUnitsPerMajor == 0 ? 0 : 2
    }
}
