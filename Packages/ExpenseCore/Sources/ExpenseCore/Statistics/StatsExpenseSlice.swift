import Foundation

/// Срез трат статистики, который открывается списком: журнал выбранной категории за период, столбик
/// «По дням» / «По часам» / «По месяцам», клетка карты года, день «Темпа» или день недели «Привычек».
public struct StatsExpenseSlice: Sendable, Hashable {
    /// Что за срез — от этого зависит заголовок списка.
    public enum Scope: Sendable, Hashable {
        /// Весь период: журнал выбранной категории.
        case period
        /// Отрезок графика: час, день или месяц.
        case bucket(StatsTimeStep)
        /// Все такие дни недели периода (нумерация `Calendar`: 1 — воскресенье).
        case weekday(Int)
    }

    public let scope: Scope
    /// Полуоткрытый `[start, end)`.
    public let interval: DateInterval
    public let filter: StatsCategoryFilter

    public init(scope: Scope, interval: DateInterval, filter: StatsCategoryFilter = .all) {
        self.scope = scope
        self.interval = interval
        self.filter = filter
    }

    /// Входит ли трата в срез.
    public func contains(_ record: ExpenseRecord, calendar: Calendar) -> Bool {
        guard interval.containsHalfOpen(record.date), filter.matches(record) else { return false }
        if case .weekday(let weekday) = scope {
            return calendar.component(.weekday, from: record.date) == weekday
        }
        return true
    }
}

/// День списка трат: начало дня, сумма и траты в порядке ленты.
public struct StatsExpenseDay: Sendable, Hashable, Identifiable {
    /// Начало дня.
    public let day: Date
    public let totalMinor: Int64
    /// Траты дня в порядке входа (лента — новые выше).
    public let expenseIDs: [UUID]

    public var id: Date { day }

    public init(day: Date, totalMinor: Int64, expenseIDs: [UUID]) {
        self.day = day
        self.totalMinor = totalMinor
        self.expenseIDs = expenseIDs
    }

    /// Начало журнала на экране статистики: первые дни целиком, пока строк меньше `rowLimit`
    /// (хотя бы один день) — день не обрывается посередине, и сумма в его заголовке совпадает со строками.
    public static func preview(_ days: [StatsExpenseDay], rowLimit: Int) -> [StatsExpenseDay] {
        var rows = 0
        var result: [StatsExpenseDay] = []
        for day in days {
            guard result.isEmpty || rows < rowLimit else { break }
            result.append(day)
            rows += day.expenseIDs.count
        }
        return result
    }
}

/// День «Темпа»: накопленное к этому дню в периоде и в прошлом периоде к тому же номеру дня.
public struct StatsPaceDay: Sendable, Hashable {
    public let current: StatsCumulativePoint
    /// `nil` — в прошлом периоде такого дня нет (он короче).
    public let previous: StatsCumulativePoint?
    /// Потрачено в сам день (не накопленное): есть ли что открыть списком.
    public let dayMinor: Int64

    public var dayNumber: Int { current.dayNumber }

    /// Разница со знаком: накопленное сейчас − в прошлом периоде; `nil` — сравнивать не с чем
    /// (такого дня нет или к нему в прошлом периоде трат не было).
    public var differenceMinor: Int64? {
        guard let previous, previous.cumulativeMinor > 0 else { return nil }
        return current.cumulativeMinor - previous.cumulativeMinor
    }

    /// Больше / меньше / примерно так же (|изменение| < `StatsThresholds.sameChange`); `nil` — как у `differenceMinor`.
    public var trend: StatsTrend? {
        guard let difference = differenceMinor, let previous else { return nil }
        let change = Double(difference) / Double(previous.cumulativeMinor)
        if abs(change) < StatsThresholds.sameChange { return .same }
        return difference > 0 ? .more : .less
    }
}

extension StatsCumulativeComparison {
    /// День `dayNumber` текущей кривой (с 1); `nil` — такого дня в ней нет (ещё не наступил).
    public func day(_ dayNumber: Int) -> StatsPaceDay? {
        guard current.indices.contains(dayNumber - 1) else { return nil }
        let point = current[dayNumber - 1]
        let before = dayNumber >= 2 ? current[dayNumber - 2].cumulativeMinor : 0
        return StatsPaceDay(
            current: point,
            previous: previous.indices.contains(dayNumber - 1) ? previous[dayNumber - 1] : nil,
            dayMinor: point.cumulativeMinor - before
        )
    }
}

extension StatisticsEngine {
    // MARK: - Срезы для списка трат

    /// Журнал выбранной категории: все траты периода.
    public func slice(period: StatsPeriod, filter: StatsCategoryFilter) -> StatsExpenseSlice {
        StatsExpenseSlice(scope: .period, interval: period.interval, filter: filter)
    }

    /// Столбик графика или клетка карты года.
    public func slice(bucket: StatsTimeBucket, step: StatsTimeStep, filter: StatsCategoryFilter) -> StatsExpenseSlice {
        StatsExpenseSlice(scope: .bucket(step), interval: bucket.interval, filter: filter)
    }

    /// Календарный день, в который попадает `date` (день «Темпа»).
    public func slice(dayContaining date: Date, filter: StatsCategoryFilter) -> StatsExpenseSlice {
        let day = calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 0)
        return StatsExpenseSlice(scope: .bucket(.day), interval: day, filter: filter)
    }

    /// День недели «Привычек»: те же дни, по которым считается средняя (`weekdayAverages`) — у идущего
    /// периода по сегодня включительно.
    public func slice(weekday: Int, period: StatsPeriod, now: Date, filter: StatsCategoryFilter) -> StatsExpenseSlice {
        StatsExpenseSlice(scope: .weekday(weekday), interval: averagingInterval(of: period, now: now), filter: filter)
    }

    /// Траты среза по дням: дни от новых к старым, внутри дня — в порядке `records` (для ленты — новые выше).
    public func expenseDays(in slice: StatsExpenseSlice, records: [ExpenseRecord]) -> [StatsExpenseDay] {
        var days: [Date: (total: Int64, ids: [UUID])] = [:]
        for record in records where slice.contains(record, calendar: calendar) {
            let day = calendar.startOfDay(for: record.date)
            days[day, default: (0, [])].total += record.amountMinor
            days[day, default: (0, [])].ids.append(record.id)
        }
        return days
            .map { StatsExpenseDay(day: $0.key, totalMinor: $0.value.total, expenseIDs: $0.value.ids) }
            .sorted { $0.day > $1.day }
    }
}
