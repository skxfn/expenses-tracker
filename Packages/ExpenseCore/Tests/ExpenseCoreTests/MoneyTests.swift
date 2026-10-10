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
        #expect(normalizedSpaces(byn.string(fromMinor: 120_050)) == "1 200,50 Br")
        #expect(normalizedSpaces(byn.string(fromMinor: 1_000)) == "10 Br")
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

/// Режимы показа сумм (design/INTEGRATION.md §5.2) на `ru_RU`. `_` в ожиданиях — U+00A0.
struct MoneyFormatterStyleTests {
    private let byn = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "ru_RU"))

    private func format(_ minor: Int64, _ style: MoneyFormatter.Style) -> String {
        byn.string(fromMinor: minor, style: style).replacingOccurrences(of: "\u{00A0}", with: "_")
    }

    @Test func phraseUsesBrAndDropsZeroCents() {
        #expect(format(3_800, .phrase) == "38_Br")
        #expect(format(41_230, .phrase) == "412,30_Br")
        #expect(format(120_050, .phrase) == "1_200,50_Br")
        #expect(byn.string(fromMinor: 3_800) == byn.string(fromMinor: 3_800, style: .phrase))
    }

    @Test func plainAlwaysHasTwoDigitsWithoutSymbol() {
        #expect(format(3_800, .plain) == "38,00")
        #expect(format(5, .plain) == "0,05")
        #expect(format(123_450, .plain) == "1_234,50")
    }

    @Test func approximateRoundsToWholeUnits() {
        #expect(format(74_240, .approximate) == "≈_742_Br")
        #expect(format(74_250, .approximate) == "≈_743_Br")
        #expect(format(160_000, .approximate) == "≈_1_600_Br")
    }

    @Test func differenceUsesMagnitudeAndWholeUnitsFromThousand() {
        #expect(format(-3_800, .difference) == "38_Br")
        #expect(format(2_380, .difference) == "23,80_Br")
        #expect(format(99_999, .difference) == "999,99_Br")
        #expect(format(100_000, .difference) == "1_000_Br")
        #expect(format(-103_850, .difference) == "1_039_Br")
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

    @Test func currencySymbolUsesOverridesAndLocale() {
        let ru = Locale(identifier: "ru_RU")
        #expect(MoneyFormatter(currencyCode: "BYN", locale: ru).currencySymbol == "Br")
        #expect(MoneyFormatter(currencyCode: "USD", locale: ru).currencySymbol == "$")
        #expect(MoneyFormatter(currencyCode: "EUR", locale: ru).currencySymbol == "€")
    }

    @Test func noNarrowOrRegularSpacesInRussianOutput() {
        let samples = [Int64(1), 99_999, 123_456_789].flatMap { minor in
            [MoneyFormatter.Style.phrase, .plain, .approximate, .difference, .calendarCell].map {
                byn.string(fromMinor: minor, style: $0)
            }
        }
        for sample in samples {
            #expect(!sample.unicodeScalars.contains { $0 == " " || $0 == "\u{202F}" }, "\(sample)")
        }
    }

    @Test func belarusianRegionKeepsSystemSymbol() {
        let ruBY = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "ru_BY"))
        #expect(ruBY.string(fromMinor: 3_800) == "38\u{00A0}Br")
        let usd = MoneyFormatter(currencyCode: "USD", locale: Locale(identifier: "ru_RU"))
        #expect(usd.string(fromMinor: 3_800) == "38\u{00A0}$")
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
