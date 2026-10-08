import Foundation

/// Вид календарного периода статистики.
public enum StatsPeriodKind: String, Sendable, Hashable, CaseIterable {
    case day
    case week
    case month
    case year

    /// Компонент календаря, которым измеряется период.
    var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

/// Период статистики: календарный (день, неделя, месяц, год) или произвольный интервал.
///
/// Интервал всегда полуоткрытый — `[start, end)`: момент `end` уже относится к следующему периоду.
/// Неделя начинается с `calendar.firstWeekday`.
public struct StatsPeriod: Sendable, Hashable {
    /// `nil` — произвольный интервал.
    public let kind: StatsPeriodKind?
    public let interval: DateInterval

    private init(kind: StatsPeriodKind?, interval: DateInterval) {
        self.kind = kind
        self.interval = interval
    }

    /// Календарный период вида `kind`, в который попадает момент `now`.
    public static func current(_ kind: StatsPeriodKind, now: Date, calendar: Calendar) -> StatsPeriod {
        let interval = calendar.dateInterval(of: kind.calendarComponent, for: now)
            ?? DateInterval(start: now, duration: 0)
        return StatsPeriod(kind: kind, interval: interval)
    }

    /// Произвольный интервал `[start, end)`.
    public static func custom(_ interval: DateInterval) -> StatsPeriod {
        StatsPeriod(kind: nil, interval: interval)
    }

    /// Предыдущий период того же вида. Для произвольного интервала — интервал той же длины,
    /// заканчивающийся в `start` (длина считается в календарных днях, поэтому DST её не сбивает).
    public func previous(in calendar: Calendar) -> StatsPeriod {
        guard let kind else { return shiftedCustom(forward: false, calendar: calendar) }
        // Календарные периоды стыкуются встык: секунда до `start` уже лежит в предыдущем.
        return .current(kind, now: interval.start.addingTimeInterval(-1), calendar: calendar)
    }

    /// Следующий период того же вида. Для произвольного интервала — интервал той же длины,
    /// начинающийся в `end`.
    public func next(in calendar: Calendar) -> StatsPeriod {
        guard let kind else { return shiftedCustom(forward: true, calendar: calendar) }
        // `end` полуоткрытого интервала — это ровно начало следующего периода.
        return .current(kind, now: interval.end, calendar: calendar)
    }

    /// Попадает ли момент в период. В отличие от `DateInterval.contains`, `end` не включается.
    public func contains(_ date: Date) -> Bool {
        interval.start <= date && date < interval.end
    }

    private func shiftedCustom(forward: Bool, calendar: Calendar) -> StatsPeriod {
        let length = calendar.dateComponents([.day, .second], from: interval.start, to: interval.end)
        let sign = forward ? 1 : -1
        let shift = DateComponents(day: (length.day ?? 0) * sign, second: (length.second ?? 0) * sign)
        let edge = forward ? interval.end : interval.start
        guard let other = calendar.date(byAdding: shift, to: edge) else { return self }
        return .custom(DateInterval(start: min(edge, other), end: max(edge, other)))
    }
}
