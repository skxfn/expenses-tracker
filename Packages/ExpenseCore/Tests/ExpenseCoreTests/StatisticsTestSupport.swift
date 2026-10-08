import Foundation
@testable import ExpenseCore

/// Общие фикстуры тестов статистики: фиксированный календарь, локаль и «сейчас».
enum StatsFixture {
    static let minsk = makeCalendar(timeZone: "Europe/Minsk")
    /// Зона с переходом на летнее время: 29.03.2026 (23 ч) и 25.10.2026 (25 ч).
    static let berlin = makeCalendar(timeZone: "Europe/Berlin")
    static let ru = Locale(identifier: "ru_RU")
    static let engine = StatisticsEngine(calendar: minsk)

    /// Четверг, 8 октября 2026, 14:30 по Минску.
    static let now = date(2026, 10, 8, 14, 30)

    static let food = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let transport = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    static func makeCalendar(timeZone identifier: String, firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        in calendar: Calendar = minsk
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    static func record(_ amountMinor: Int64, _ date: Date, _ categoryID: UUID? = nil) -> ExpenseRecord {
        ExpenseRecord(amountMinor: amountMinor, date: date, categoryID: categoryID)
    }

    /// Набор трат вокруг октября 2026 с граничными моментами.
    static let records: [ExpenseRecord] = [
        record(10_000, date(2026, 9, 15, 12), food),
        record(2_000, date(2026, 9, 30, 23, 59, 59), transport),  // последний миг сентября
        record(3_000, date(2026, 10, 1), food),                  // первый миг октября
        record(2_000, date(2026, 10, 5, 9), transport),          // понедельник
        record(4_000, date(2026, 10, 8, 10), food),              // сегодня до now
        record(1_000, date(2026, 10, 8, 20)),                     // сегодня после now, без категории
        record(5_000, date(2026, 10, 20, 12), food),             // будущая дата внутри октября
        record(7_000, date(2026, 11, 1), food)                   // первый миг ноября — не октябрь
    ]

    static var october: StatsPeriod { .current(.month, now: now, calendar: minsk) }
}
