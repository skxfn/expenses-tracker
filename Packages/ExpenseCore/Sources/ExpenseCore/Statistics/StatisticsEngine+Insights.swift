import Foundation

extension StatisticsEngine {
    // MARK: - Какие блоки показывать

    /// «Темп» есть у недели, месяца и года; для «Дня» и «Своего» скрыт (§8, п. 16).
    public func showsPace(for period: StatsPeriod) -> Bool {
        switch period.kind {
        case .week, .month, .year: true
        case .day, nil: false
        }
    }

    /// «Привычки» (средние по дням недели) — только у месяца и года: у дня и недели они повторяют
    /// столбики «По дням», у своего периода дней недели может не набраться (§4.8).
    public func showsHabits(for period: StatsPeriod) -> Bool {
        switch period.kind {
        case .month, .year: true
        case .day, .week, nil: false
        }
    }

    /// «По часам» в виде «День» — только для сегодняшнего дня: у трат прошлых дней время случайное (§8, п. 15).
    public func showsHourly(for period: StatsPeriod, now: Date) -> Bool {
        period.kind == .day && period.contains(now)
    }

    /// Достаточно ли данных для «Темпа»: прошло ≥ `paceMinimumDays` дней периода (включая сегодня)
    /// и за них ≥ `paceMinimumCount` трат. Для прошедшего периода «прошло» — все его дни.
    public func hasEnoughDataForPace(
        for period: StatsPeriod,
        records: [ExpenseRecord],
        now: Date,
        filter: StatsCategoryFilter = .all
    ) -> Bool {
        let elapsed = averagingInterval(of: period, now: now)
        let count = records.count { filter.matches($0) && elapsed.containsHalfOpen($0.date) }
        return slices(of: elapsed, by: .day).count >= StatsThresholds.paceMinimumDays
            && count >= StatsThresholds.paceMinimumCount
    }

    /// Достаточно ли данных для «Привычек»: траты хотя бы в `habitsMinimumDays` разных днях
    /// периода (для текущего — по сегодня включительно).
    public func hasEnoughDataForHabits(
        for period: StatsPeriod,
        records: [ExpenseRecord],
        now: Date,
        filter: StatsCategoryFilter = .all
    ) -> Bool {
        let days = slices(of: averagingInterval(of: period, now: now), by: .day)
        let spendingDays = aggregate(records.filter(filter.matches), into: days).count { $0.count > 0 }
        return spendingDays >= StatsThresholds.habitsMinimumDays
    }

    // MARK: - Прогноз

    /// Прогноз итога к концу идущей недели, месяца или года: `итог × дней_в_периоде / прошло_дней`
    /// по тратам с начала периода по сегодня включительно. `nil` — период не идёт или это «День»/«Свой».
    public func forecast(
        for period: StatsPeriod,
        records: [ExpenseRecord],
        now: Date,
        filter: StatsCategoryFilter = .all
    ) -> StatsForecast? {
        guard showsPace(for: period), period.contains(now) else { return nil }
        let elapsed = averagingInterval(of: period, now: now)
        let elapsedDayCount = slices(of: elapsed, by: .day).count
        let dayCount = slices(of: period.interval, by: .day).count
        let total = Self.total(of: records.filter { filter.matches($0) && elapsed.containsHalfOpen($0.date) })
        let (scaled, overflow) = total.multipliedReportingOverflow(by: Int64(dayCount))
        guard !overflow, elapsedDayCount > 0 else { return nil }
        return StatsForecast(
            projectedMinor: Money.divideRounded(scaled, by: elapsedDayCount),
            elapsedDayCount: elapsedDayCount,
            dayCount: dayCount
        )
    }

    // MARK: - Привычки

    /// Средние по дням недели и выводы «Больше всего тратится по пятницам»,
    /// «В будни тратится больше, чем в выходные» / «почти поровну».
    public func habits(
        for period: StatsPeriod,
        records: [ExpenseRecord],
        now: Date,
        filter: StatsCategoryFilter = .all
    ) -> StatsHabits {
        let averages = weekdayAverages(for: period, records: records, now: now, filter: filter)
        let peak = averages.max { $1.averageMinor > $0.averageMinor }
        return StatsHabits(
            averages: averages,
            peakWeekday: peak.flatMap { $0.averageMinor > 0 ? $0.weekday : nil },
            split: Self.weekSplit(of: averages)
        )
    }

    /// Средняя за день в будни (пн–пт) против выходных (сб–вс). `nil` — в периоде нет будней или выходных.
    private static func weekSplit(of averages: [StatsWeekdayAverage]) -> StatsWeekSplit? {
        let weekend: Set<Int> = [1, 7] // воскресенье и суббота в нумерации `Calendar`
        func average(_ isWeekend: Bool) -> Double? {
            let days = averages.filter { weekend.contains($0.weekday) == isWeekend }
            let dayCount = days.reduce(0) { $0 + $1.dayCount }
            guard dayCount > 0 else { return nil }
            return Double(days.reduce(0) { $0 + $1.totalMinor }) / Double(dayCount)
        }
        guard let weekdays = average(false), let weekends = average(true) else { return nil }
        let larger = max(weekdays, weekends)
        if larger == 0 || abs(weekdays - weekends) < StatsThresholds.weekSplitTie * larger { return .even }
        return weekdays > weekends ? .weekdays : .weekend
    }
}
