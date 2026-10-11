import Foundation

/// Форматирование сумм из minor-единиц. Копейки показываются, только если они есть:
/// `120000` → «1 200 ⃅», `1250` → «12,50 ⃅».
public struct MoneyFormatter: Sendable {
    /// Как показать сумму (design/copy.json → voice «Деньги», design/INTEGRATION.md §5.2).
    public enum Style: Sendable {
        /// Во фразах: с символом, нулевые копейки отбрасываются — «38 ⃅», «412,30 ⃅».
        case phrase
        /// Ячейки, плитки, строки ленты, топ: всегда 2 знака, без символа — «38,00».
        case plain
        /// Округлённая сумма — прогноз и шит периода: целые единицы, «≈ 742 ⃅».
        /// Прогноз до двух значащих цифр округляет `StatsForecast.roundedMinor`.
        case approximate
        /// Разница во фразе-сравнении, по модулю: до 1 000 — как `phrase`, от 1 000 — целыми и без «≈»:
        /// «на 23,80 ⃅ меньше», «на 1 039 ⃅ меньше».
        case difference
        /// Клетка календаря (`cal.cell.amount`): «64,10» · «1 234» · «12 тыс»; по-английски — «12K».
        case calendarCell
        /// Целые единицы без символа — пороги шкалы heat в легенде (`cal.legend.items`): «25», «1 000».
        case wholeUnits
    }

    public let currencyCode: String
    public let locale: Locale
    /// Обозначение BYN: знак или код (настройка «Обозначение»). На другие валюты не влияет.
    public let symbolStyle: CurrencySymbolStyle

    public init(currencyCode: String, locale: Locale = .autoupdatingCurrent, symbolStyle: CurrencySymbolStyle = .default) {
        self.currencyCode = currencyCode
        self.locale = locale
        self.symbolStyle = symbolStyle
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
            difference(Self.differenceMagnitude(minor))
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

    /// Разница по модулю так, как её показывает `.difference`: до 1 000 — точно, от 1 000 — целыми.
    /// Для озвучки фразы-сравнения: VoiceOver читает то же число, что на экране (`103_850` → `103_900`).
    public static func differenceMagnitude(_ minor: Int64) -> Int64 {
        let magnitude = minor == .min ? .max : abs(minor)
        return magnitude >= differenceWholeUnitsFromMinor ? Money.roundedToWholeUnits(magnitude) : magnitude
    }

    // MARK: - Пороги

    /// Разница во фразе от 1 000 единиц — целыми.
    static let differenceWholeUnitsFromMinor: Int64 = 100_000
    /// Клетка календаря: копейки — только до 100 (design/copy.json → `cal.cell.amount.why`;
    /// тексты главнее INTEGRATION.md §5.2, где указано 1 000).
    static let calendarCellWholeUnitsFromMinor: Int64 = 10_000
    /// Клетка календаря: от 10 000 — «тыс».
    static let calendarCellThousandsFromMinor: Int64 = 1_000_000

    /// Знак белорусского рубля (design/INTEGRATION.md §3.3.1): U+20C5, предварительный код Unicode 19.0.
    /// В системных шрифтах его нет — в приложении рисуется своим шрифтом (`CurrencySignFont`).
    public static let belarusianRubleSign = "\u{20C5}"
    /// ISO-код белорусского рубля — единственная валюта с настройкой «Обозначение».
    public static let belarusianRubleCode = "BYN"

    /// Обозначение BYN не из ICU: ICU даёт «Br» (`ru_BY`) или «BYN» (`ru_RU`), а в суммах нужен знак
    /// или код по настройке. `nil` — другая валюта, обозначение даёт ICU.
    private var symbolOverride: String? {
        guard currencyCode == Self.belarusianRubleCode else { return nil }
        return switch symbolStyle {
        case .sign: Self.belarusianRubleSign
        case .code: currencyCode
        }
    }

    /// Разделитель дробной части для поля ввода суммы (`AmountInput.sanitize`): «,» в ru, «.» в en-US.
    public var decimalSeparator: Character {
        locale.decimalSeparator?.first ?? AmountInput.decimalSeparator
    }

    /// Символ валюты для подписи рядом с суммой: «⃅» или «BYN», «$», «€», «₽».
    public var currencySymbol: String {
        if let symbolOverride { return symbolOverride }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol
    }

    // MARK: - Внутреннее

    private func currency(_ minor: Int64, fractionLength: Int) -> String {
        // Обозначение BYN — после числа через U+00A0 и в ru, и в en (§5.2, E7: «1,412.60 ⃅»):
        // ICU en-US поставил бы код перед числом («BYN 1,412.60»).
        if let symbolOverride {
            return number(minor, fractionLength: fractionLength) + TextSpacing.nonBreaking + symbolOverride
        }
        let style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
            .precision(.fractionLength(fractionLength))
        return Money.major(fromMinor: minor).formatted(style)
    }

    private func number(_ minor: Int64, fractionLength: Int) -> String {
        Money.major(fromMinor: minor).formatted(
            .number
                .locale(locale)
                .precision(.fractionLength(fractionLength))
        )
    }

    /// `shown` — уже из `differenceMagnitude`: от 1 000 — целое число единиц, нулевые копейки отбрасываются.
    private func difference(_ shown: Int64) -> String {
        currency(shown, fractionLength: fractionLength(for: shown))
    }

    private func calendarCell(_ minor: Int64) -> String {
        guard minor >= Self.calendarCellWholeUnitsFromMinor else { return number(minor, fractionLength: 2) }
        let whole = Money.roundedToWholeUnits(minor)
        guard whole >= Self.calendarCellThousandsFromMinor else { return number(whole, fractionLength: 0) }
        let thousands = Money.divideRounded(minor, by: Int(Self.calendarCellThousandsFromMinor / 10))
        return number(thousands * Money.minorUnitsPerMajor, fractionLength: 0) + thousandsSuffix
    }

    /// `cal.cell.amount.thousands` в каталоге App недоступен Core: «12 тыс» (ru), «12K» (en).
    private var thousandsSuffix: String {
        locale.language.languageCode == .english ? "K" : TextSpacing.nonBreaking + "тыс"
    }

    private func fractionLength(for minor: Int64) -> Int {
        minor % Money.minorUnitsPerMajor == 0 ? 0 : 2
    }
}
