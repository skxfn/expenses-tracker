import Foundation

/// Суммы хранятся целым числом minor-единиц (сотых долей валюты): 1 единица = 100 minor.
/// Масштаб фиксирован для любой валюты приложения.
public enum Money {
    public static let minorUnitsPerMajor: Int64 = 100
    /// Наибольшая сумма одной траты: 99 999 999 999,99 (11 целых знаков поля). Сумма даже ~900 тыс.
    /// таких трат помещается в `Int64` — итоги статистики складываются без переполнения.
    public static let maxAmountMinor: Int64 = 9_999_999_999_999

    /// `1250` → `12.5`. Точно, без двоичной погрешности.
    public static func major(fromMinor minor: Int64) -> Decimal {
        Decimal(minor) / Decimal(minorUnitsPerMajor)
    }

    /// `12.345` → `1235`: округление до сотых (половина — от нуля).
    /// `nil`, если значение не число или не помещается в `Int64`.
    public static func minor(fromMajor major: Decimal) -> Int64? {
        guard !major.isNaN else { return nil }
        var scaled = major * Decimal(minorUnitsPerMajor)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        // Описание целого Decimal — цифры без экспоненты; Int64(_:) сам отсекает переполнение.
        return Int64(rounded.description)
    }

    /// Разбор ввода пользователя в minor-единицы: `"12,5"` → `1250`, `"1 200"` → `120000`.
    /// Разделитель дробной части — `,` или `.`, не больше двух знаков после него;
    /// пробелы (включая неразрывные) игнорируются как разделители разрядов.
    /// `nil` для пустой строки, мусора, знаков `+`/`-`, нуля и переполнения.
    public static func minor(fromInput input: String) -> Int64? {
        let compact = input.filter { !$0.isWhitespace }
        let parts = compact.split(omittingEmptySubsequences: false) { $0 == "," || $0 == "." }
        guard parts.count <= 2 else { return nil }

        let integerPart = parts[0]
        let fractionPart = parts.count == 2 ? parts[1] : ""
        guard
            !(integerPart.isEmpty && fractionPart.isEmpty),
            fractionPart.count <= 2,
            (integerPart + fractionPart).allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }

        let paddedFraction = fractionPart.padding(toLength: 2, withPad: "0", startingAt: 0)
        guard
            let units = Int64(integerPart.isEmpty ? "0" : integerPart),
            let cents = Int64(paddedFraction)
        else { return nil }

        let (scaled, multiplyOverflow) = units.multipliedReportingOverflow(by: minorUnitsPerMajor)
        let (total, addOverflow) = scaled.addingReportingOverflow(cents)
        guard !multiplyOverflow, !addOverflow, total > 0 else { return nil }
        return total
    }

    /// Целочисленное деление с округлением половины от нуля. При `divisor <= 0` — 0.
    static func divideRounded(_ value: Int64, by divisor: Int) -> Int64 {
        guard divisor > 0 else { return 0 }
        let divisor = Int64(divisor)
        let quotient = value / divisor
        let remainder = value % divisor
        guard remainder.magnitude * 2 >= divisor.magnitude else { return quotient }
        return quotient + (value < 0 ? -1 : 1)
    }

    /// Округление до целых единиц валюты (половина — от нуля): `74_250` → `74_300`.
    /// Публично для строк каталога, где «≈» уже стоит (`period.range.meta`): там сумма — `.phrase` от округлённой.
    public static func roundedToWholeUnits(_ minor: Int64) -> Int64 {
        divideRounded(minor, by: Int(minorUnitsPerMajor)) * minorUnitsPerMajor
    }

    /// Округление до `digits` значащих цифр в целых единицах, но не мельче единицы:
    /// `158_000` (1 580) → `160_000` (1 600) при двух цифрах; `8_745` (87,45) → `8_700` (87).
    static func roundedToSignificantDigits(_ minor: Int64, digits: Int) -> Int64 {
        var step = minorUnitsPerMajor
        var limit = minorUnitsPerMajor
        for _ in 0..<max(digits, 1) {
            let (next, overflow) = limit.multipliedReportingOverflow(by: 10)
            guard !overflow else { return roundedToWholeUnits(minor) }
            limit = next
        }
        while minor.magnitude >= limit.magnitude {
            let (nextLimit, overflow) = limit.multipliedReportingOverflow(by: 10)
            guard !overflow else { break }
            step *= 10
            limit = nextLimit
        }
        return divideRounded(minor, by: Int(step)) * step
    }
}
