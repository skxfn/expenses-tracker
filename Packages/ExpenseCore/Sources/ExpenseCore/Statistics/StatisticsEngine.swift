import Foundation

/// Чистый движок статистики: только значения на входе и выходе, без SwiftData.
///
/// Все расчёты детерминированы: календарь задаётся при создании, текущий момент `now`
/// передаётся в методы явно. Деньги считаются только в `Int64`.
public struct StatisticsEngine: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    // MARK: - Сводка

    /// Итог, количество, средняя трата в день и сравнение с предыдущим периодом.
    ///
    /// Для текущего (незавершённого) периода средняя считается по дням с начала периода
    /// по сегодняшний включительно и только по тратам этих дней; для прошлых и будущих — по всем дням.
    public func summary(
        for period: StatsPeriod,
        records: [ExpenseRecord],
        now: Date,
        filter: StatsCategoryFilter = .all
    ) -> StatsSummary {
        let matching = records.filter(filter.matches)
        let inPeriod = matching.filter { period.contains($0.date) }
        let previousPeriod = period.previous(in: calendar)
        let previousTotal = Self.total(of: matching.filter { previousPeriod.contains($0.date) })

        let averaging = averagingInterval(of: period, now: now)
        let dayCount = slices(of: averaging, by: .day).count
        let averagedTotal = Self.total(of: inPeriod.filter { averaging.containsHalfOpen($0.date) })

        let total = Self.total(of: inPeriod)
        let change: Double? = previousTotal == 0
            ? nil
            : Double(total - previousTotal) / Double(previousTotal)

        return StatsSummary(
            totalMinor: total,
            count: inPeriod.count,
            averagePerDayMinor: Self.divideRounded(averagedTotal, by: dayCount),
            averagedDayCount: dayCount,
            previousTotalMinor: previousTotal,
            change: change
        )
    }

    // MARK: - Категории

    /// Разбивка по категориям, по убыванию суммы. Расходы без категории — строка с `categoryID == nil`.
    /// При равных суммах порядок детерминирован: больше трат → выше, строка без категории — ниже.
    public func categoryBreakdown(for period: StatsPeriod, records: [ExpenseRecord]) -> [StatsCategoryShare] {
        var groups: [UUID?: (total: Int64, count: Int)] = [:]
        var grandTotal: Int64 = 0
        for record in records where period.contains(record.date) {
            groups[record.categoryID, default: (0, 0)].total += record.amountMinor
            groups[record.categoryID, default: (0, 0)].count += 1
            grandTotal += record.amountMinor
        }
        return groups
            .map { categoryID, group in
                StatsCategoryShare(
                    categoryID: categoryID,
                    totalMinor: group.total,
                    count: group.count,
                    share: grandTotal == 0 ? 0 : Double(group.total) / Double(grandTotal)
                )
            }
            .sorted(by: Self.isOrderedBefore)
    }

    // MARK: - Временной ряд

    /// Временной ряд с нулями в пустых отрезках. Без явного `step` шаг выбирается по периоду:
    /// день → часы, неделя и месяц → дни, год → месяцы; произвольный интервал — часы (до суток),
    /// дни (до 62 дней) или месяцы. Крайние отрезки обрезаются границами периода.
    public func timeSeries(
        for period: StatsPeriod,
        records: [ExpenseRecord],
        step: StatsTimeStep? = nil,
        filter: StatsCategoryFilter = .all
    ) -> StatsTimeSeries {
        let step = step ?? defaultStep(for: period)
        let bucketIntervals = slices(of: period.interval, by: step.calendarComponent)
        let sums = aggregate(records.filter(filter.matches), into: bucketIntervals)
        let buckets = zip(bucketIntervals, sums).map { interval, sum in
            StatsTimeBucket(interval: interval, totalMinor: sum.total, count: sum.count)
        }
        return StatsTimeSeries(step: step, buckets: buckets)
    }

    // MARK: - Накопительная кривая

    /// Накопительные суммы по дням периода и предыдущего периода («этот месяц vs прошлый»).
    /// Текущая кривая для незавершённого периода обрывается на сегодняшнем дне.
    public func cumulativeComparison(
        for period: StatsPeriod,
        records: [ExpenseRecord],
        now: Date,
        filter: StatsCategoryFilter = .all
    ) -> StatsCumulativeComparison {
        let matching = records.filter(filter.matches)
        return StatsCumulativeComparison(
            current: cumulativePoints(over: averagingInterval(of: period, now: now), records: matching),
            previous: cumulativePoints(over: period.previous(in: calendar).interval, records: matching)
        )
    }

    // MARK: - Дни недели

    /// Средние траты по дням недели: сумма трат в этот день недели / число таких дней в периоде.
    /// Для текущего периода учитываются дни по сегодняшний включительно.
    /// Всегда 7 элементов, первый — `calendar.firstWeekday`.
    public func weekdayAverages(
        for period: StatsPeriod,
        records: [ExpenseRecord],
        now: Date,
        filter: StatsCategoryFilter = .all
    ) -> [StatsWeekdayAverage] {
        let days = slices(of: averagingInterval(of: period, now: now), by: .day)
        let sums = aggregate(records.filter(filter.matches), into: days)
        var dayCounts: [Int: Int] = [:]
        var totals: [Int: Int64] = [:]
        for (day, sum) in zip(days, sums) {
            let weekday = calendar.component(.weekday, from: day.start)
            dayCounts[weekday, default: 0] += 1
            totals[weekday, default: 0] += sum.total
        }
        return (0..<Self.daysInWeek).map { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % Self.daysInWeek + 1
            let dayCount = dayCounts[weekday] ?? 0
            let total = totals[weekday] ?? 0
            return StatsWeekdayAverage(
                weekday: weekday,
                dayCount: dayCount,
                totalMinor: total,
                averageMinor: Self.divideRounded(total, by: dayCount)
            )
        }
    }

    // MARK: - Топ трат

    /// `limit` самых крупных трат периода. При равной сумме выше более поздняя.
    public func topExpenses(
        for period: StatsPeriod,
        records: [ExpenseRecord],
        limit: Int,
        filter: StatsCategoryFilter = .all
    ) -> [ExpenseRecord] {
        guard limit > 0 else { return [] }
        let sorted = records
            .filter { period.contains($0.date) && filter.matches($0) }
            .sorted(by: Self.isLarger)
        return Array(sorted.prefix(limit))
    }

    // MARK: - Внутреннее

    private static let daysInWeek = 7

    func defaultStep(for period: StatsPeriod) -> StatsTimeStep {
        switch period.kind {
        case .day:
            return .hour
        case .week, .month:
            return .day
        case .year:
            return .month
        case nil:
            let dayCount = slices(of: period.interval, by: .day).count
            if dayCount <= 1 { return .hour }
            return dayCount <= 62 ? .day : .month
        }
    }

    /// Часть периода, по которой считаются средние: для текущего — до конца сегодняшнего дня.
    private func averagingInterval(of period: StatsPeriod, now: Date) -> DateInterval {
        guard period.contains(now), let today = calendar.dateInterval(of: .day, for: now) else {
            return period.interval
        }
        return DateInterval(start: period.interval.start, end: min(today.end, period.interval.end))
    }

    /// Нарезка полуоткрытого интервала по календарной единице; крайние куски обрезаются.
    /// Учитывает DST: сутки могут длиться 23 или 25 часов.
    private func slices(of interval: DateInterval, by component: Calendar.Component) -> [DateInterval] {
        var result: [DateInterval] = []
        var cursor = interval.start
        while cursor < interval.end {
            guard let unit = calendar.dateInterval(of: component, for: cursor), unit.end > cursor else { break }
            let end = min(unit.end, interval.end)
            result.append(DateInterval(start: cursor, end: end))
            cursor = end
        }
        return result
    }

    /// Суммы и количества трат по кускам; траты вне кусков отбрасываются.
    private func aggregate(
        _ records: [ExpenseRecord],
        into slices: [DateInterval]
    ) -> [(total: Int64, count: Int)] {
        var sums = [(total: Int64, count: Int)](repeating: (0, 0), count: slices.count)
        for record in records {
            guard let index = Self.sliceIndex(for: record.date, in: slices) else { continue }
            sums[index].total += record.amountMinor
            sums[index].count += 1
        }
        return sums
    }

    private func cumulativePoints(over interval: DateInterval, records: [ExpenseRecord]) -> [StatsCumulativePoint] {
        let days = slices(of: interval, by: .day)
        let sums = aggregate(records, into: days)
        var running: Int64 = 0
        return days.indices.map { index in
            running += sums[index].total
            return StatsCumulativePoint(dayNumber: index + 1, date: days[index].start, cumulativeMinor: running)
        }
    }

    /// Бинарный поиск куска, содержащего дату. Куски идут подряд и по возрастанию.
    private static func sliceIndex(for date: Date, in slices: [DateInterval]) -> Int? {
        var low = 0
        var high = slices.count
        while low < high {
            let middle = (low + high) / 2
            if slices[middle].end <= date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low < slices.count, slices[low].start <= date else { return nil }
        return low
    }

    private static func total(of records: [ExpenseRecord]) -> Int64 {
        records.reduce(0) { $0 + $1.amountMinor }
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

    private static func isOrderedBefore(_ lhs: StatsCategoryShare, _ rhs: StatsCategoryShare) -> Bool {
        if lhs.totalMinor != rhs.totalMinor { return lhs.totalMinor > rhs.totalMinor }
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        switch (lhs.categoryID, rhs.categoryID) {
        case let (left?, right?): return left.uuidString < right.uuidString
        case (.some, nil): return true
        default: return false
        }
    }

    private static func isLarger(_ lhs: ExpenseRecord, _ rhs: ExpenseRecord) -> Bool {
        if lhs.amountMinor != rhs.amountMinor { return lhs.amountMinor > rhs.amountMinor }
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private extension DateInterval {
    /// Попадание в полуоткрытый интервал `[start, end)`; штатный `contains` включает `end`.
    func containsHalfOpen(_ date: Date) -> Bool {
        start <= date && date < end
    }
}
