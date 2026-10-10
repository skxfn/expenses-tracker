import Foundation

/// Ввод суммы в шите записи (INTEGRATION §4.9, §6 «Ввод суммы»): системная цифровая клавиатура
/// и быстрые суммы, которые прибавляются к введённой. Текст поля всегда разбирает `Money.minor(fromInput:)`.
public enum AmountInput {
    /// Разделитель дробной части в поле: приложение только на русском, точку с клавиатуры заменяем запятой.
    public static let decimalSeparator: Character = ","
    /// Знаков после запятой — minor-единицы.
    public static let fractionDigits = 2
    /// Целых знаков в поле: 11 — до 99 999 999 999,99 (`Money.maxAmountMinor`).
    public static let maxIntegerDigits = 11
    /// Наибольшая сумма поля — предел одной траты.
    public static let maxMinor: Int64 = Money.maxAmountMinor
    /// Быстрые суммы, целые единицы валюты (DESIGN.md → Chips, AGENTS.md: фиксированные).
    public static let quickAmounts: [Int64] = [5, 10, 20, 50, 100]

    public struct Sanitized: Equatable, Sendable {
        public let text: String
        /// Третий знак после запятой отброшен — объявить `add.amount.invalid`.
        public let droppedFractionDigits: Bool
    }

    /// Приводит набранное к виду «1200», «12,5», «0,»: только цифры ASCII и одна запятая (точка → запятая),
    /// не больше двух знаков после неё и `maxIntegerDigits` до неё, без ведущих нулей.
    /// Запятая первой даёт «0,». Пробелы, знаки и прочие символы отбрасываются.
    public static func sanitize(_ input: String) -> Sanitized {
        var integer = ""
        var fraction = ""
        var hasSeparator = false
        var droppedFraction = false
        for character in input {
            if character == "," || character == "." {
                hasSeparator = true
            } else if character.isASCII, character.isNumber {
                if hasSeparator {
                    if fraction.count < fractionDigits {
                        fraction.append(character)
                    } else {
                        droppedFraction = true
                    }
                } else if integer.count < maxIntegerDigits {
                    integer.append(character)
                }
            }
        }
        let significant = String(integer.drop { $0 == "0" })
        let normalizedInteger = significant.isEmpty && (!integer.isEmpty || hasSeparator) ? "0" : significant
        let text = hasSeparator
            ? normalizedInteger + String(decimalSeparator) + fraction
            : normalizedInteger
        return Sanitized(text: text, droppedFractionDigits: droppedFraction)
    }

    /// Сумма после быстрой суммы `units` (целых единиц): прибавляется к введённой, пустое поле — просто `units`.
    /// `nil` — переполнение или больше `maxMinor`: поле тогда не меняется.
    public static func adding(_ units: Int64, to text: String) -> Int64? {
        guard units > 0 else { return nil }
        let current = Money.minor(fromInput: text) ?? 0
        let (added, multiplyOverflow) = units.multipliedReportingOverflow(by: Money.minorUnitsPerMajor)
        let (sum, addOverflow) = current.addingReportingOverflow(added)
        guard !multiplyOverflow, !addOverflow, sum <= maxMinor else { return nil }
        return sum
    }
}
