/// Подписи и деления осей графиков статистики (design/INTEGRATION.md §6 «Графики», макет `04-stats`):
/// редкие подписи дней «1, 8, 15, 22, 29» вместо подписи у каждого столбика и «круглые» деления оси сумм.
public enum StatsChartAxes {
    /// Индексы подписанных отрезков оси: каждый `step`-й от первого (у месяца — 1, 8, 15, 22, 29)
    /// и закреплённые (`pinned`: сегодня, последний день). Обычная подпись ближе `minimumGap` к закреплённой
    /// убирается, чтобы подписи не слипались. Отрезков не больше `step` — подписаны все.
    public static func labeledIndices(count: Int, step: Int = 7, pinned: [Int] = [], minimumGap: Int = 3) -> [Int] {
        guard count > 0 else { return [] }
        guard count > step, step > 0 else { return Array(0..<count) }
        let pinned = Set(pinned.filter { (0..<count).contains($0) })
        let regular = stride(from: 0, to: count, by: step).filter { index in
            pinned.allSatisfy { abs($0 - index) >= minimumGap }
        }
        return Set(regular).union(pinned).sorted()
    }

    /// «Круглые» деления оси сумм от нуля, не выше `maxMinor`: шаг 1, 2, 2,5 или 5 × 10ⁿ целых единиц —
    /// самый мелкий, при котором делений не больше `maximumCount` (1 600 → 500, 1 000, 1 500).
    /// Пусто, если максимум меньше одной единицы.
    public static func valueTicks(upTo maxMinor: Int64, maximumCount: Int = 3) -> [Int64] {
        guard maxMinor >= Money.minorUnitsPerMajor, maximumCount > 0 else { return [] }
        var magnitude = Money.minorUnitsPerMajor
        while true {
            for step in niceSteps(magnitude) where maxMinor / step <= Int64(maximumCount) {
                return (1...maxMinor / step).map { step * $0 }
            }
            let (next, overflow) = magnitude.multipliedReportingOverflow(by: 10)
            guard !overflow else { return [] }
            magnitude = next
        }
    }

    /// Шаги одного разряда по возрастанию: 1, 2, 2,5 (только от десятков — иначе дробный), 5.
    private static func niceSteps(_ magnitude: Int64) -> [Int64] {
        let double = magnitude.multipliedReportingOverflow(by: 2)
        let five = magnitude.multipliedReportingOverflow(by: 5)
        let hasQuarter = magnitude >= 10 * Money.minorUnitsPerMajor && !five.overflow
        return [magnitude]
            + (double.overflow ? [] : [double.partialValue])
            + (hasQuarter ? [five.partialValue / 2] : [])
            + (five.overflow ? [] : [five.partialValue])
    }
}
