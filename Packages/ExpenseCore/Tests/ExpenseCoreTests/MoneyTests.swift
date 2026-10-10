import Foundation
import Testing
@testable import ExpenseCore

struct MoneyTests {
    // MARK: - minor ↔ Decimal

    @Test func majorFromMinorIsExact() {
        #expect(Money.major(fromMinor: 1250) == Decimal(string: "12.5"))
        #expect(Money.major(fromMinor: 1) == Decimal(string: "0.01"))
        #expect(Money.major(fromMinor: 0) == 0)
    }

    @Test(arguments: [
        ("12.5", Int64(1250)),
        ("12.345", 1235),
        ("12.344", 1234),
        ("-1.005", -101),
        ("0.004", 0)
    ])
    func minorFromMajorRoundsToCents(major: String, expected: Int64) throws {
        let value = try #require(Decimal(string: major, locale: Locale(identifier: "en_US_POSIX")))
        #expect(Money.minor(fromMajor: value) == expected)
    }

    @Test func minorFromMajorRejectsOverflowAndNaN() throws {
        let huge = try #require(Decimal(string: "1e30"))
        #expect(Money.minor(fromMajor: huge) == nil)
        #expect(Money.minor(fromMajor: .nan) == nil)
    }

    @Test(arguments: [Int64(1), 99, 1250, 120_000, .max, .min])
    func minorRoundTripsThroughDecimal(minor: Int64) {
        #expect(Money.minor(fromMajor: Money.major(fromMinor: minor)) == minor)
    }

    // MARK: - Разбор ввода

    @Test(arguments: [
        ("12,5", Int64(1250)),
        ("12.50", 1250),
        ("1 200", 120_000),
        ("1\u{00A0}200,75", 120_075),
        ("1\u{202F}000", 100_000),
        (" 7 ", 700),
        ("0,01", 1),
        (",5", 50),
        ("5,", 500),
        ("007", 700),
        ("92233720368547758,07", .max)
    ])
    func parsesValidInput(input: String, expected: Int64) {
        #expect(Money.minor(fromInput: input) == expected)
    }

    @Test(arguments: [
        "", " ", ",", ".", "abc", "12a", "0", "0,00", "-5", "+5", "1,2,3", "1,200.50",
        "12,345", "1e3", "١٢", "92233720368547758,08", "99999999999999999999"
    ])
    func rejectsInvalidInput(input: String) {
        #expect(Money.minor(fromInput: input) == nil)
    }

    // MARK: - Форматирование

    @Test func formatsWithCurrencySymbolAndHidesZeroCents() {
        let usd = MoneyFormatter(currencyCode: "USD", locale: Locale(identifier: "en_US"))
        #expect(usd.string(fromMinor: 120_050) == "$1,200.50")
        #expect(usd.string(fromMinor: 120_000) == "$1,200")
        #expect(usd.string(fromMinor: 5) == "$0.05")

        let byn = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "ru_BY"))
        #expect(normalizedSpaces(byn.string(fromMinor: 120_050)) == "1 200,50 \u{20C5}")
        #expect(normalizedSpaces(byn.string(fromMinor: 1_000)) == "10 \u{20C5}")
    }

    @Test func editingStringUsesLocaleSeparatorWithoutGrouping() {
        let ru = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "ru_RU"))
        #expect(ru.editingString(fromMinor: 1250) == "12,50")
        #expect(ru.editingString(fromMinor: 120_000) == "1200")

        let en = MoneyFormatter(currencyCode: "USD", locale: Locale(identifier: "en_US"))
        #expect(en.editingString(fromMinor: 1250) == "12.50")
    }

    @Test(arguments: [Int64(1), 50, 1250, 120_000, 123_456_789])
    func editingStringParsesBack(minor: Int64) {
        for identifier in ["ru_RU", "en_US", "de_DE"] {
            let formatter = MoneyFormatter(currencyCode: "EUR", locale: Locale(identifier: identifier))
            #expect(Money.minor(fromInput: formatter.editingString(fromMinor: minor)) == minor, "\(identifier)")
        }
    }

    /// Разделители разрядов в ICU — неразрывные пробелы разных видов; для сравнения приводим к обычным.
    private func normalizedSpaces(_ string: String) -> String {
        String(string.map { $0.isWhitespace ? " " : $0 })
    }
}

/// Режимы показа сумм (design/INTEGRATION.md §5.2) на `ru_RU`. `_` в ожиданиях — U+00A0, знак рубля — U+20C5.
struct MoneyFormatterStyleTests {
    private let byn = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "ru_RU"))

    private func format(_ minor: Int64, _ style: MoneyFormatter.Style) -> String {
        byn.string(fromMinor: minor, style: style).replacingOccurrences(of: "\u{00A0}", with: "_")
    }

    @Test func phraseUsesSignAndDropsZeroCents() {
        #expect(format(3_800, .phrase) == "38_\u{20C5}")
        #expect(format(41_230, .phrase) == "412,30_\u{20C5}")
        #expect(format(120_050, .phrase) == "1_200,50_\u{20C5}")
        #expect(byn.string(fromMinor: 3_800) == byn.string(fromMinor: 3_800, style: .phrase))
    }

    @Test func plainAlwaysHasTwoDigitsWithoutSymbol() {
        #expect(format(3_800, .plain) == "38,00")
        #expect(format(5, .plain) == "0,05")
        #expect(format(123_450, .plain) == "1_234,50")
    }

    @Test func approximateRoundsToWholeUnits() {
        #expect(format(74_240, .approximate) == "≈_742_\u{20C5}")
        #expect(format(74_250, .approximate) == "≈_743_\u{20C5}")
        #expect(format(160_000, .approximate) == "≈_1_600_\u{20C5}")
    }

    @Test func differenceUsesMagnitudeAndWholeUnitsFromThousand() {
        #expect(format(-3_800, .difference) == "38_\u{20C5}")
        #expect(format(2_380, .difference) == "23,80_\u{20C5}")
        #expect(format(99_999, .difference) == "999,99_\u{20C5}")
        #expect(format(100_000, .difference) == "1_000_\u{20C5}")
        #expect(format(-103_850, .difference) == "1_039_\u{20C5}")
        #expect(!format(.min, .difference).isEmpty)
    }

    @Test(arguments: [
        (Int64(6_410), "64,10"),
        (9_999, "99,99"),
        (10_000, "100"),
        (99_999, "1_000"),
        (100_000, "1_000"),
        (123_449, "1_234"),
        (999_960, "10_тыс"),
        (1_234_567, "12_тыс"),
        (1_250_000, "13_тыс")
    ])
    func calendarCell(minor: Int64, expected: String) {
        #expect(format(minor, .calendarCell) == expected)
    }

    @Test func wholeUnitsRoundWithoutSymbol() {
        #expect(format(2_500, .wholeUnits) == "25")
        #expect(format(12_550, .wholeUnits) == "126")
        #expect(format(100_000, .wholeUnits) == "1_000")
    }

    @Test func currencySymbolUsesOverridesAndLocale() {
        let ru = Locale(identifier: "ru_RU")
        #expect(MoneyFormatter(currencyCode: "BYN", locale: ru).currencySymbol == "\u{20C5}")
        #expect(MoneyFormatter(currencyCode: "USD", locale: ru).currencySymbol == "$")
        #expect(MoneyFormatter(currencyCode: "EUR", locale: ru).currencySymbol == "€")
    }

    @Test func noNarrowOrRegularSpacesInRussianOutput() {
        let samples = [Int64(1), 99_999, 123_456_789].flatMap { minor in
            [MoneyFormatter.Style.phrase, .plain, .approximate, .difference, .calendarCell, .wholeUnits].map {
                byn.string(fromMinor: minor, style: $0)
            }
        }
        for sample in samples {
            #expect(!sample.unicodeScalars.contains { $0 == " " || $0 == "\u{202F}" }, "\(sample)")
        }
    }

    /// ICU в `ru_BY` даёт «Br», в `ru_RU` — «BYN»: обозначение BYN не зависит от региона.
    @Test func belarusianRegionUsesSignToo() {
        let ruBY = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "ru_BY"))
        #expect(ruBY.string(fromMinor: 3_800) == "38\u{00A0}\u{20C5}")
        #expect(ruBY.currencySymbol == "\u{20C5}")
        let usd = MoneyFormatter(currencyCode: "USD", locale: Locale(identifier: "ru_RU"))
        #expect(usd.string(fromMinor: 3_800) == "38\u{00A0}$")
    }
}

/// Настройка «Обозначение» (design/INTEGRATION.md §3.3.1): знак U+20C5 или код BYN; другие валюты — ICU.
struct CurrencySymbolStyleTests {
    private static let allStyles: [MoneyFormatter.Style] = [.phrase, .plain, .approximate, .difference, .calendarCell, .wholeUnits]
    private let ru = Locale(identifier: "ru_RU")

    private func formatter(_ symbolStyle: CurrencySymbolStyle, code: String = "BYN") -> MoneyFormatter {
        MoneyFormatter(currencyCode: code, locale: ru, symbolStyle: symbolStyle)
    }

    @Test func defaultIsSign() {
        #expect(CurrencySymbolStyle.default == .sign)
        #expect(MoneyFormatter(currencyCode: "BYN", locale: ru).symbolStyle == .sign)
    }

    @Test(arguments: [
        (CurrencySymbolStyle.sign, "\u{20C5}"),
        (.code, "BYN")
    ])
    func symbolFollowsStyleInEveryAmountStyle(symbolStyle: CurrencySymbolStyle, symbol: String) {
        let byn = formatter(symbolStyle)
        let nb = "\u{00A0}"
        #expect(byn.currencySymbol == symbol)
        #expect(byn.string(fromMinor: 3_800, style: .phrase) == "38\(nb)\(symbol)")
        #expect(byn.string(fromMinor: 41_230, style: .phrase) == "412,30\(nb)\(symbol)")
        #expect(byn.string(fromMinor: 160_000, style: .approximate) == "≈\(nb)1\(nb)600\(nb)\(symbol)")
        #expect(byn.string(fromMinor: -2_380, style: .difference) == "23,80\(nb)\(symbol)")
        #expect(byn.string(fromMinor: 103_850, style: .difference) == "1\(nb)039\(nb)\(symbol)")
        // Без обозначения — одинаково при любой настройке.
        #expect(byn.string(fromMinor: 3_800, style: .plain) == "38,00")
        #expect(byn.string(fromMinor: 123_449, style: .calendarCell) == "1\(nb)234")
        #expect(byn.string(fromMinor: 2_500, style: .wholeUnits) == "25")
    }

    @Test(arguments: CurrencySymbolStyle.allCases)
    func symbolIsSeparatedByNoBreakSpaceOnly(symbolStyle: CurrencySymbolStyle) {
        let byn = formatter(symbolStyle)
        for minor in [Int64(1), 3_800, 99_999, 123_456_789] {
            for style in Self.allStyles {
                let text = byn.string(fromMinor: minor, style: style)
                #expect(!text.unicodeScalars.contains { $0 == " " || $0 == "\u{202F}" }, "\(text)")
                #expect(!text.contains("Br"), "\(text)")
                if text.contains(byn.currencySymbol) {
                    #expect(text.hasSuffix("\u{00A0}" + byn.currencySymbol), "\(text)")
                }
            }
        }
    }

    @Test(arguments: CurrencySymbolStyle.allCases)
    func otherCurrenciesIgnoreStyle(symbolStyle: CurrencySymbolStyle) {
        let usd = formatter(symbolStyle, code: "USD")
        #expect(usd.currencySymbol == "$")
        #expect(usd.string(fromMinor: 3_800) == "38\u{00A0}$")
        let eur = formatter(symbolStyle, code: "EUR")
        #expect(eur.string(fromMinor: 41_230, style: .approximate) == "≈\u{00A0}412\u{00A0}€")
    }
}

struct CurrencySettingsTests {
    @Test(arguments: [("ru_BY", "BYN"), ("en_US", "USD"), ("de_DE", "EUR"), ("ru", "BYN")])
    func defaultCodeComesFromRegion(identifier: String, expected: String) {
        #expect(CurrencySettings.defaultCode(for: Locale(identifier: identifier)) == expected)
    }

    @Test func currencyListsCoverAllCommonCodesWithoutDuplicates() {
        let popular = CurrencySettings.popularCodes
        let other = CurrencySettings.otherCodes
        #expect(popular.first == "BYN")
        #expect(Set(popular).count == popular.count)
        #expect(Set(popular).isDisjoint(with: other))
        #expect(Set(popular + other) == Set(Locale.commonISOCurrencyCodes))
        #expect(other == other.sorted())
    }

    @Test func currencyCodeReadsWithoutWriting() throws {
        let temporary = try TemporaryDefaults()
        let code = CurrencySettings.currencyCode(in: temporary.defaults, locale: Locale(identifier: "en_US"))

        #expect(code == "USD")
        #expect(temporary.defaults.string(forKey: SettingsKeys.currencyCode) == nil)
    }

    @Test func ensureCurrencyCodePersistsDefaultOnce() throws {
        let temporary = try TemporaryDefaults()

        let first = CurrencySettings.ensureCurrencyCode(in: temporary.defaults, locale: Locale(identifier: "ru_BY"))
        let second = CurrencySettings.ensureCurrencyCode(in: temporary.defaults, locale: Locale(identifier: "en_US"))

        #expect(first == "BYN")
        #expect(second == "BYN")
        #expect(CurrencySettings.currencyCode(in: temporary.defaults, locale: Locale(identifier: "en_US")) == "BYN")
    }
}
