import Foundation

/// Суммы хранятся целым числом minor-единиц (сотых долей валюты): 1 единица = 100 minor.
/// Масштаб фиксирован для любой валюты приложения.
public enum Money {
    public static let minorUnitsPerMajor: Int64 = 100

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
}
