import Foundation
import Testing
@testable import ExpenseCore

/// Сравнение «к той же дате» (D5, design/INTEGRATION.md §4.7).
@Suite struct StatisticsComparisonTests {
    private typealias F = StatsFixture
    private let engine = F.engine

    private func comparison(_ kind: StatsPeriodKind, now: Date) -> DateInterval {
        engine.comparisonInterval(for: .current(kind, now: now, calendar: F.minsk), now: now)
    }

    private func interval(_ start: Date, _ end: Date) -> DateInterval {
        DateInterval(start: start, end: end)
    }

    // MARK: - Отрезок сравнения

    @Test func currentMonthComparesWithSameDays() {
        #expect(comparison(.month, now: F.now) == interval(F.date(2026, 9, 1), F.date(2026, 9, 9)))
        #expect(comparison(.month, now: F.date(2026, 10, 1, 0, 0, 1)) == interval(F.date(2026, 9, 1), F.date(2026, 9, 2)))
        #expect(comparison(.month, now: F.date(2026, 10, 30, 12)) == interval(F.date(2026, 9, 1), F.date(2026, 10, 1)))
    }

    @Test func monthEdgesTakeWholeShorterPreviousMonth() {
        // 31 октября → весь сентябрь.
        #expect(comparison(.month, now: F.date(2026, 10, 31, 23, 59)) == interval(F.date(2026, 9, 1), F.date(2026, 10, 1)))
        // 30 марта → весь февраль.
        #expect(comparison(.month, now: F.date(2026, 3, 30, 9)) == interval(F.date(2026, 2, 1), F.date(2026, 3, 1)))
        // Високосный 2024: 28 марта → 1–28 февраля, 29 марта → весь февраль (29 дней).
        #expect(comparison(.month, now: F.date(2024, 3, 28)) == interval(F.date(2024, 2, 1), F.date(2024, 2, 29)))
        #expect(comparison(.month, now: F.date(2024, 3, 29)) == interval(F.date(2024, 2, 1), F.date(2024, 3, 1)))
        // Январь сравнивается с декабрём прошлого года.
        #expect(comparison(.month, now: F.date(2027, 1, 5)) == interval(F.date(2026, 12, 1), F.date(2026, 12, 6)))
    }

    @Test func dayComparesWithWholeYesterday() {
        #expect(comparison(.day, now: F.now) == interval(F.date(2026, 10, 7), F.date(2026, 10, 8)))
    }

    @Test func weekComparesWithSameWeekdays() {
        // Четверг 8 октября: пн–чт прошлой недели.
        #expect(comparison(.week, now: F.now) == interval(F.date(2026, 9, 28), F.date(2026, 10, 2)))
        // Воскресенье — вся прошлая неделя.
        #expect(comparison(.week, now: F.date(2026, 10, 11, 22)) == interval(F.date(2026, 9, 28), F.date(2026, 10, 5)))
    }

    @Test func yearCountsDaysSoLeapYearShiftsByOneDay() {
        // 8 октября 2025 — 281-й день; в високосном 2024 первые 281 день кончаются 7 октября.
        #expect(comparison(.year, now: F.date(2025, 10, 8, 12)) == interval(F.date(2024, 1, 1), F.date(2024, 10, 8)))
        // 8 октября 2024 — 282-й день; в 2023 первые 282 дня кончаются 9 октября.
        #expect(comparison(.year, now: F.date(2024, 10, 8, 12)) == interval(F.date(2023, 1, 1), F.date(2023, 10, 10)))
        // Без високосного года — та же дата.
        #expect(comparison(.year, now: F.now) == interval(F.date(2025, 1, 1), F.date(2025, 10, 9)))
    }

    @Test func pastAndCustomPeriodsCompareWithWholePrevious() {
        let september = F.october.previous(in: F.minsk)
        #expect(engine.comparisonInterval(for: september, now: F.now) == interval(F.date(2026, 8, 1), F.date(2026, 9, 1)))

        // Свой период, даже если он идёт, — с предыдущим диапазоном той же длины.
        let custom = StatsPeriod.custom(interval(F.date(2026, 10, 5), F.date(2026, 10, 15)))
        #expect(engine.comparisonInterval(for: custom, now: F.now) == interval(F.date(2026, 9, 25), F.date(2026, 10, 5)))
    }

    // MARK: - Сводка и фраза

    @Test func summaryUsesSameDatesAndTrend() {
        let records = [
            F.record(5_000, F.date(2026, 9, 3)),
            F.record(9_000, F.date(2026, 9, 20)),  // после «той же даты» — не считается
            F.record(4_000, F.date(2026, 10, 2))
        ]
        let summary = engine.summary(for: F.october, records: records, now: F.now)
        #expect(summary.previousTotalMinor == 5_000)
        #expect(summary.differenceMinor == -1_000)
        #expect(summary.change == -0.2)
        #expect(summary.trend == .less)
        #expect(summary.comparisonReference == .lastMonth)

        let more = engine.summary(for: F.october, records: records + [F.record(3_000, F.now)], now: F.now)
        #expect(more.trend == .more)
        #expect(more.differenceMinor == 2_000)
    }

    @Test(arguments: [
        (Int64(10_050), StatsTrend.same),   // +0,5 %
        (9_901, .same),                     // −0,99 %
        (10_100, .more),                    // ровно 1 % — уже не «примерно»
        (9_900, .less),
        (10_000, .same)
    ])
    func trendThreshold(total: Int64, expected: StatsTrend) {
        let records = [F.record(10_000, F.date(2026, 9, 2)), F.record(total, F.date(2026, 10, 2))]
        #expect(engine.summary(for: F.october, records: records, now: F.now).trend == expected)
    }

    @Test func noPreviousWhenComparedPartIsEmpty() {
        let summary = engine.summary(for: F.october, records: [F.record(100, F.date(2026, 10, 2))], now: F.now)
        #expect(summary.trend == .noPrevious)
        #expect(engine.summary(for: F.october, records: [], now: F.now).trend == .noPrevious)
    }

    @Test func referencesByKindAndTense() {
        func reference(_ period: StatsPeriod) -> StatsComparisonReference {
            engine.summary(for: period, records: [], now: F.now).comparisonReference
        }
        let today = StatsPeriod.current(.day, now: F.now, calendar: F.minsk)
        let week = StatsPeriod.current(.week, now: F.now, calendar: F.minsk)
        let year = StatsPeriod.current(.year, now: F.now, calendar: F.minsk)
        let custom = StatsPeriod.custom(interval(F.date(2026, 10, 5), F.date(2026, 10, 8)))

        #expect(reference(today) == .yesterday)
        #expect(reference(today.previous(in: F.minsk)) == .dayBefore)
        #expect(reference(week) == .lastWeek)
        #expect(reference(week.previous(in: F.minsk)) == .range(interval(F.date(2026, 9, 21), F.date(2026, 9, 28))))
        #expect(reference(F.october) == .lastMonth)
        #expect(reference(F.october.previous(in: F.minsk)) == .month(8))
        #expect(reference(year) == .lastYear)
        #expect(reference(year.previous(in: F.minsk)) == .year(2024))
        #expect(reference(custom) == .range(interval(F.date(2026, 10, 2), F.date(2026, 10, 5))))
    }
}
