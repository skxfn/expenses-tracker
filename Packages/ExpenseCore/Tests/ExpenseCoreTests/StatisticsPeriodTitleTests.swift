import Foundation
import Testing
@testable import ExpenseCore

/// Точная пунктуация (тире, тонкие пробелы) зависит от версии CLDR в ОС,
/// поэтому для диапазонов проверяются смысловые части строки.
@Suite struct StatisticsPeriodTitleTests {
    private typealias F = StatsFixture

    private func title(_ period: StatsPeriod, locale: Locale = F.ru) -> String {
        period.title(now: F.now, calendar: F.minsk, locale: locale)
    }

    @Test func relativeDayTitles() {
        let today = StatsPeriod.current(.day, now: F.now, calendar: F.minsk)
        #expect(title(today) == "Сегодня")
        #expect(title(today.previous(in: F.minsk)) == "Вчера")
        #expect(title(today.next(in: F.minsk)) == "Завтра")
        #expect(title(today, locale: Locale(identifier: "en_US")) == "Today")
    }

    @Test func plainDayTitles() {
        let october6 = StatsPeriod.current(.day, now: F.date(2026, 10, 6, 18), calendar: F.minsk)
        #expect(title(october6) == "6 октября")

        let lastYear = StatsPeriod.current(.day, now: F.date(2025, 10, 6), calendar: F.minsk)
        #expect(title(lastYear).hasPrefix("6 октября 2025"))
    }

    @Test func weekTitles() {
        let current = StatsPeriod.current(.week, now: F.now, calendar: F.minsk)
        let currentTitle = title(current)
        #expect(currentTitle.hasPrefix("5"))
        #expect(currentTitle.hasSuffix("11 окт."))
        #expect(!currentTitle.contains("2026"))
        #expect(!currentTitle.contains("сент."))

        let crossMonth = title(current.previous(in: F.minsk))
        #expect(crossMonth.hasPrefix("28 сент."))
        #expect(crossMonth.hasSuffix("4 окт."))

        let crossYear = title(StatsPeriod.current(.week, now: F.date(2027, 1, 1), calendar: F.minsk))
        #expect(crossYear.hasPrefix("28 дек. 2026"))
        #expect(crossYear.contains("3 янв. 2027"))
    }

    @Test func monthAndYearTitles() {
        #expect(title(F.october).hasPrefix("Октябрь 2026"))
        #expect(title(F.october, locale: Locale(identifier: "en_US")) == "October 2026")

        let year = StatsPeriod.current(.year, now: F.now, calendar: F.minsk)
        #expect(title(year) == "2026")
    }

    @Test func customTitleTreatsEndAsExclusive() {
        let firstHalf = StatsPeriod.custom(DateInterval(start: F.date(2026, 10, 1), end: F.date(2026, 10, 15)))
        let rangeTitle = title(firstHalf)
        #expect(rangeTitle.hasPrefix("1"))
        #expect(rangeTitle.hasSuffix("14 окт."))

        let withinDay = StatsPeriod.custom(DateInterval(start: F.date(2026, 10, 6, 10), end: F.date(2026, 10, 6, 18)))
        #expect(title(withinDay) == "6 окт.")

        let endsMidday = StatsPeriod.custom(DateInterval(start: F.date(2026, 10, 1, 12), end: F.date(2026, 10, 3, 12)))
        #expect(title(endsMidday).hasSuffix("3 окт."))
    }
}
