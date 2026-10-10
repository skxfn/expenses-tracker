import Foundation

/// Дата траты в шите записи: сегмент «Сегодня · Вчера · Дата…» (`add.date.*`).
/// «Сегодня» и «Вчера» вычисляются в момент сохранения: шит, открытый в 23:59 и сохранённый в 00:01,
/// запишет трату на новый день. Для «сегодня» хранится момент записи (INTEGRATION §8 п. 15).
public enum EntryDate: Hashable, Sendable {
    case today
    case yesterday
    /// Точный момент: другой день из шита даты или календаря, исходная дата при правке.
    case moment(Date)

    /// Что подсвечено в сегменте.
    public enum Segment: Hashable, Sendable {
        case today
        case yesterday
        /// Третий пункт показывает дату («5 окт»).
        case other(Date)
    }

    /// Дата новой траты: `nil` — сегодня; день из календаря — как выбранный в шите даты.
    public static func forNewExpense(on day: Date?, now: Date, calendar: Calendar) -> EntryDate {
        guard let day else { return .today }
        return picked(day, now: now, calendar: calendar)
    }

    /// День, выбранный в календаре: сегодня и вчера становятся пунктами сегмента,
    /// другой день получает время `now` (время траты за прошлые дни не выбирается).
    public static func picked(_ day: Date, now: Date, calendar: Calendar) -> EntryDate {
        if calendar.isDate(day, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return .yesterday
        }
        return .moment(combining(day: day, timeOf: now, calendar: calendar))
    }

    /// Дата, с которой трата сохраняется.
    public func resolved(now: Date, calendar: Calendar) -> Date {
        switch self {
        case .today: now
        case .yesterday: calendar.date(byAdding: .day, value: -1, to: now) ?? now
        case .moment(let date): date
        }
    }

    /// Пункт сегмента. Точный момент сегодняшнего или вчерашнего дня (правка) подсвечивает «Сегодня» / «Вчера».
    public func segment(now: Date, calendar: Calendar) -> Segment {
        switch self {
        case .today: return .today
        case .yesterday: return .yesterday
        case .moment(let date):
            switch Self.picked(date, now: now, calendar: calendar) {
            case .today: return .today
            case .yesterday: return .yesterday
            case .moment: return .other(date)
            }
        }
    }

    /// Год, месяц и день `day` со временем `now`.
    static func combining(day: Date, timeOf now: Date, calendar: Calendar) -> Date {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        parts.hour = time.hour
        parts.minute = time.minute
        parts.second = time.second
        parts.nanosecond = time.nanosecond
        return calendar.date(from: parts) ?? day
    }
}
