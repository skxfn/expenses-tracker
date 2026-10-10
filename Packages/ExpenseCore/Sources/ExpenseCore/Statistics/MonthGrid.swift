import Foundation

/// Раскладка месяца для календаря: недели по 7 мест, неделя начинается с `calendar.firstWeekday`,
/// места до первого и после последнего дня — `nil`. Дни — начала суток в `calendar`.
public struct MonthGrid: Sendable, Hashable {
    /// Месяц как период статистики (`[1-е число, 1-е число следующего)`).
    public let period: StatsPeriod
    /// Начала всех дней месяца по порядку.
    public let days: [Date]
    /// Недели по 7 мест; число недель — 4–6.
    public let weeks: [[Date?]]
    /// Дни недели в порядке колонок, нумерация `Calendar`: 1 — воскресенье … 7 — суббота.
    public let weekdays: [Int]

    private let calendar: Calendar

    /// Месяц, в который попадает `date`.
    public init(containing date: Date, calendar: Calendar) {
        self.calendar = calendar
        period = .current(.month, now: date, calendar: calendar)

        let start = period.interval.start
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
        days = (0..<dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map(calendar.startOfDay)
        }

        let firstWeekday = calendar.firstWeekday
        weekdays = (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }

        let leading = (calendar.component(.weekday, from: start) - firstWeekday + 7) % 7
        let trailing = (7 - (leading + days.count) % 7) % 7
        let slots: [Date?] = Array(repeating: nil, count: leading) + days + Array(repeating: nil, count: trailing)
        weeks = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
    }

    /// Первый день месяца.
    public var start: Date { period.interval.start }

    public func previous() -> MonthGrid {
        MonthGrid(containing: period.previous(in: calendar).interval.start, calendar: calendar)
    }

    public func next() -> MonthGrid {
        MonthGrid(containing: period.next(in: calendar).interval.start, calendar: calendar)
    }

    /// Попадает ли момент в месяц (полуоткрытый интервал).
    public func contains(_ date: Date) -> Bool {
        period.contains(date)
    }

    /// День этого месяца с тем же числом, что у `date` (31-е → последний день короткого месяца),
    /// но не позже дня `latest`: при переходе по месяцам выбранный день не уходит в будущее.
    public func day(matching date: Date, notAfter latest: Date) -> Date {
        guard !days.isEmpty else { return start }
        let number = calendar.component(.day, from: date)
        let candidate = days[min(max(number, 1), days.count) - 1]
        let latestDay = calendar.startOfDay(for: latest)
        guard candidate > latestDay else { return candidate }
        return contains(latestDay) ? latestDay : candidate
    }
}
