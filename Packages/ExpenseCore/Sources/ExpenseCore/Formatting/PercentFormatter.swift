/// Проценты по D7 (design/copy.json): целые, слитно со знаком — «35%», меньше 1 — «<1%».
/// Системный формат `ru` даёт «35 %», поэтому свой.
public enum PercentFormatter {
    /// - Parameter share: доля 0…1. Ноль, отрицательное и NaN — «0%».
    public static func string(fromShare share: Double) -> String {
        guard share > 0 else { return "0%" }
        guard share >= 0.01 else { return "<1%" }
        // Допуск на двоичное представление: 0,345 · 100 в Double — 34,4999…, а показать нужно «35%».
        let percent = (share * 100 + 1e-9).rounded(.toNearestOrAwayFromZero)
        return "\(Int(percent))%"
    }
}
