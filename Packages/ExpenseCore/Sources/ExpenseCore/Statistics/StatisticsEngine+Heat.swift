import Foundation

extension StatisticsEngine {
    // MARK: - Шкала календаря и тепловой карты

    /// Шкала heat для года, в который попадает `date` (§8, п. 11): границы — квартили сумм дней
    /// с тратами (ближайший ранг), округлённые до «круглых» чисел (`roundedToNiceNumber`).
    /// Одна шкала для календаря месяца и тепловой карты года. `nil` — в году нет трат.
    /// Дневные суммы для клеток — `timeSeries(for:records:step: .day)`, день с максимумом — `peak`.
    public func heatScale(
        forYearContaining date: Date,
        records: [ExpenseRecord],
        filter: StatsCategoryFilter = .all
    ) -> StatsHeatScale? {
        let year = StatsPeriod.current(.year, now: date, calendar: calendar)
        let sums = timeSeries(for: year, records: records, step: .day, filter: filter).buckets
            .map(\.totalMinor)
            .filter { $0 > 0 }
            .sorted()
        guard !sums.isEmpty else { return nil }
        var thresholds: [Int64] = []
        for quarter in 1...3 {
            let index = (quarter * sums.count + 3) / 4 - 1 // ⌈quarter · n / 4⌉ − 1
            var value = Self.roundedToNiceNumber(sums[index])
            if let last = thresholds.last, value <= last {
                value = last + Self.niceStep(for: last)
            }
            thresholds.append(value)
        }
        return StatsHeatScale(thresholds: thresholds)
    }

    /// «Круглое» число не меньше одной единицы валюты: `2_340` (23,40) → `2_500` (25).
    static func roundedToNiceNumber(_ minor: Int64) -> Int64 {
        let step = niceStep(for: minor)
        return max(Money.divideRounded(minor, by: Int(step)) * step, Money.minorUnitsPerMajor)
    }

    /// Шаг «круглых» чисел — половина разряда в целых единицах: до 10 — 1, 10–99 — 5, 100–999 — 50, …
    static func niceStep(for minor: Int64) -> Int64 {
        var step = Money.minorUnitsPerMajor
        var limit = 10 * Money.minorUnitsPerMajor
        while minor.magnitude >= limit.magnitude {
            let (next, overflow) = limit.multipliedReportingOverflow(by: 10)
            guard !overflow else { break }
            step = limit / 2
            limit = next
        }
        return step
    }
}
