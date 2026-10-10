import Foundation

/// Форматирование сумм из minor-единиц. Копейки показываются, только если они есть:
/// `120000` → «1 200 Br», `1250` → «12,50 Br».
public struct MoneyFormatter: Sendable {
    /// Как показать сумму (design/copy.json → voice «Деньги», design/INTEGRATION.md §5.2).
    public enum Style: Sendable {
        /// Во фразах: с символом, нулевые копейки отбрасываются — «38 Br», «412,30 Br».
        case phrase
        /// Ячейки, плитки, строки ленты, топ: всегда 2 знака, без символа — «38,00».
        case plain
        /// Округлённая сумма — прогноз и шит периода: целые единицы, «≈ 742 Br».
        /// Прогноз до двух значащих цифр округляет `StatsForecast.roundedMinor`.
        case approximate
        /// Разница во фразе-сравнении, по модулю: до 1 000 — как `phrase`, от 1 000 — целыми и без «≈»:
        /// «на 23,80 Br меньше», «на 1 039 Br меньше».
        case difference
        /// Клетка календаря (`cal.cell.amount`): «64,10» · «1 234» · «12 тыс».
        case calendarCell
        /// Целые единицы без символа — пороги шкалы heat в легенде (`cal.legend.items`): «25», «1 000».
        case wholeUnits
    }

    public let currencyCode: String
    public let locale: Locale

    public init(currencyCode: String, locale: Locale = .autoupdatingCurrent) {
        self.currencyCode = currencyCode
        self.locale = locale
    }

    /// Сумма в нужном виде. Пробелы — U+00A0 (`TextSpacing.normalized`).
    public func string(fromMinor minor: Int64, style: Style = .phrase) -> String {
        let text = switch style {
        case .phrase:
            currency(minor, fractionLength: fractionLength(for: minor))
        case .plain:
            number(minor, fractionLength: 2)
        case .approximate:
            "≈" + TextSpacing.nonBreaking + currency(Money.roundedToWholeUnits(minor), fractionLength: 0)
        case .difference:
            difference(minor == .min ? .max : abs(minor))
        case .calendarCell:
            calendarCell(minor)
        case .wholeUnits:
            number(Money.roundedToWholeUnits(minor), fractionLength: 0)
        }
        return TextSpacing.normalized(text)
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

    // MARK: - Пороги

    /// Разница во фразе от 1 000 единиц — целыми.
    static let differenceWholeUnitsFromMinor: Int64 = 100_000
    /// Клетка календаря: копейки — только до 100 (design/copy.json → `cal.cell.amount.why`;
    /// тексты главнее INTEGRATION.md §5.2, где указано 1 000).
    static let calendarCellWholeUnitsFromMinor: Int64 = 10_000
    /// Клетка календаря: от 10 000 — «тыс».
    static let calendarCellThousandsFromMinor: Int64 = 1_000_000

    /// Символы, которые ICU даёт не везде: «Br» для BYN есть только в `ru_BY`, а в `ru_RU` — «BYN».
    /// В суммах всегда «Br» (design/copy.json → глоссарий «Валюта в суммах»).
    private static let symbolOverrides = ["BYN": "Br"]

    /// Символ валюты для подписи рядом с суммой: «Br», «$», «€», «₽».
    public var currencySymbol: String {
        if let symbol = Self.symbolOverrides[currencyCode] { return symbol }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol
    }

    // MARK: - Внутреннее

    private func currency(_ minor: Int64, fractionLength: Int) -> String {
        let text = Money.major(fromMinor: minor).formatted(
            .currency(code: currencyCode)
                .locale(locale)
                .precision(.fractionLength(fractionLength))
        )
        guard let symbol = Self.symbolOverrides[currencyCode] else { return text }
        return text.replacingOccurrences(of: currencyCode, with: symbol)
    }

    private func number(_ minor: Int64, fractionLength: Int) -> String {
        Money.major(fromMinor: minor).formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(fractionLength))
        )
    }

    private func difference(_ magnitude: Int64) -> String {
        guard magnitude >= Self.differenceWholeUnitsFromMinor else {
            return currency(magnitude, fractionLength: fractionLength(for: magnitude))
        }
        return currency(Money.roundedToWholeUnits(magnitude), fractionLength: 0)
    }

    private func calendarCell(_ minor: Int64) -> String {
        guard minor >= Self.calendarCellWholeUnitsFromMinor else { return number(minor, fractionLength: 2) }
        let whole = Money.roundedToWholeUnits(minor)
        guard whole >= Self.calendarCellThousandsFromMinor else { return number(whole, fractionLength: 0) }
        let thousands = Money.divideRounded(minor, by: Int(Self.calendarCellThousandsFromMinor / 10))
        return number(thousands * Money.minorUnitsPerMajor, fractionLength: 0) + TextSpacing.nonBreaking + "тыс"
    }

    private func fractionLength(for minor: Int64) -> Int {
        minor % Money.minorUnitsPerMajor == 0 ? 0 : 2
    }
}
