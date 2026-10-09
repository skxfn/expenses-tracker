import Foundation
import Testing
@testable import ExpenseCore

/// Заголовок периода по D7: свои сокращения без точки, год — только если он не текущий,
/// внутри даты — U+00A0, в составном диапазоне — « – » с U+00A0 перед тире.
@Suite struct StatisticsPeriodTitleTests {
    private typealias F = StatsFixture
    private static let nbsp = "\u{00A0}"

    private func title(_ period: StatsPeriod, now: Date = F.now) -> PeriodTitle {
        RussianDateFormatter(calendar: F.minsk, now: now).title(for: period)
    }

    private func parts(_ title: PeriodTitle) -> [String] {
        title.parts.map { ($0.isSecondary ? "~" : "") + $0.text.replacingOccurrences(of: Self.nbsp, with: "_") }
    }

    @Test func relativeDayTitles() {
        let today = StatsPeriod.current(.day, now: F.now, calendar: F.minsk)
        #expect(title(today) == PeriodTitle(style: .word, parts: [.init("Сегодня")]))
        #expect(title(today.previous(in: F.minsk)).text == "Вчера")
    }

    @Test func plainDayTitles() {
        let october6 = StatsPeriod.current(.day, now: F.date(2026, 10, 6, 18), calendar: F.minsk)
        #expect(title(october6).style == .dates)
        #expect(parts(title(october6)) == ["6", "~_окт"])
        // Завтра словом не называется: вперёд шапка не листает дальше сегодня.
        #expect(title(StatsPeriod.current(.day, now: F.date(2026, 10, 9), calendar: F.minsk)).text == "9\(Self.nbsp)окт")

        let lastYear = StatsPeriod.current(.day, now: F.date(2025, 10, 6), calendar: F.minsk)
        #expect(parts(title(lastYear)) == ["6", "~_окт_2025"])
    }

    @Test func weekTitles() {
        let current = StatsPeriod.current(.week, now: F.now, calendar: F.minsk)
        #expect(title(current).style == .dates)
        #expect(parts(title(current)) == ["5–11", "~_окт"])

        let crossMonth = title(current.previous(in: F.minsk))
        #expect(parts(crossMonth) == ["28", "~_сен", "_– 4", "~_окт"])
        #expect(crossMonth.text == "28\(Self.nbsp)сен\(Self.nbsp)– 4\(Self.nbsp)окт")

        // Неделя через Новый год, смотрим из 2027: годов нет («28 дек – 3 янв»).
        let newYearWeek = StatsPeriod.current(.week, now: F.date(2027, 1, 1), calendar: F.minsk)
        #expect(parts(title(newYearWeek, now: F.date(2027, 1, 2))) == ["28", "~_дек", "_– 3", "~_янв"])
        // Из 2026 конец недели в чужом году — годы у обоих концов.
        #expect(parts(title(newYearWeek)) == ["28", "~_дек_2026", "_– 3", "~_янв_2027"])

        let lastYearWeek = StatsPeriod.current(.week, now: F.date(2025, 10, 8), calendar: F.minsk)
        #expect(parts(title(lastYearWeek)) == ["6–12", "~_окт_2025"])
    }

    @Test func monthAndYearTitles() {
        #expect(title(F.october) == PeriodTitle(style: .word, parts: [.init("Октябрь")]))
        let lastYear = StatsPeriod.current(.month, now: F.date(2025, 5, 3), calendar: F.minsk)
        #expect(parts(title(lastYear)) == ["Май", "~_2025"])

        let year = StatsPeriod.current(.year, now: F.now, calendar: F.minsk)
        #expect(title(year) == PeriodTitle(style: .word, parts: [.init("2026")]))
        #expect(title(year.previous(in: F.minsk)).text == "2025")
    }

    @Test func customTitleTreatsEndAsExclusive() {
        let firstHalf = StatsPeriod.custom(DateInterval(start: F.date(2026, 10, 1), end: F.date(2026, 10, 15)))
        #expect(parts(title(firstHalf)) == ["1–14", "~_окт"])

        let withinDay = StatsPeriod.custom(DateInterval(start: F.date(2026, 10, 6, 10), end: F.date(2026, 10, 6, 18)))
        #expect(parts(title(withinDay)) == ["6", "~_окт"])

        let endsMidday = StatsPeriod.custom(DateInterval(start: F.date(2026, 10, 1, 12), end: F.date(2026, 10, 3, 12)))
        #expect(title(endsMidday).text == "1–3\(Self.nbsp)окт")

        let may = StatsPeriod.custom(DateInterval(start: F.date(2026, 5, 5), end: F.date(2026, 5, 8)))
        #expect(title(may).text == "5–7\(Self.nbsp)мая")
    }
}
