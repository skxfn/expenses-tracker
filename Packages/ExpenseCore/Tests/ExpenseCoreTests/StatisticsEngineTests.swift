import Foundation
import Testing
@testable import ExpenseCore

@Suite struct StatisticsEngineTests {
    private typealias F = StatsFixture
    private let engine = F.engine

    // MARK: - Сводка

    @Test func summaryOfCurrentMonth() {
        let summary = engine.summary(for: F.october, records: F.records, now: F.now)
        #expect(summary.totalMinor == 15_000)
        #expect(summary.count == 5)
        // 1–8 октября; трата 20 октября в среднюю не входит: (3000 + 2000 + 4000 + 1000) / 8.
        #expect(summary.averagedDayCount == 8)
        #expect(summary.averagePerDayMinor == 1_250)
        #expect(summary.previousTotalMinor == 12_000)
        #expect(summary.change == 0.25)
    }

    @Test func summaryOfPastMonthUsesAllDays() {
        let september = F.october.previous(in: F.minsk)
        let summary = engine.summary(for: september, records: F.records, now: F.now)
        #expect(summary.totalMinor == 12_000)
        #expect(summary.count == 2)
        #expect(summary.averagedDayCount == 30)
        #expect(summary.averagePerDayMinor == 400)
        #expect(summary.previousTotalMinor == 0)
        #expect(summary.change == nil)
    }

    @Test func summaryOfYears() {
        let current = StatsPeriod.current(.year, now: F.now, calendar: F.minsk)
        #expect(engine.summary(for: current, records: [], now: F.now).averagedDayCount == 281)

        let leap = StatsPeriod.current(.year, now: F.date(2024, 6, 1), calendar: F.minsk)
        #expect(engine.summary(for: leap, records: [], now: F.now).averagedDayCount == 366)
    }

    @Test func summaryDecreaseAndFilters() {
        let food = engine.summary(for: F.october, records: F.records, now: F.now, filter: .category(F.food))
        #expect(food.totalMinor == 12_000)
        #expect(food.count == 3)
        #expect(food.averagePerDayMinor == 875)
        #expect(food.previousTotalMinor == 10_000)
        #expect(food.change == 0.2)

        let transport = engine.summary(for: F.october, records: F.records, now: F.now, filter: .category(F.transport))
        #expect(transport.change == 0)

        let uncategorized = engine.summary(for: F.october, records: F.records, now: F.now, filter: .uncategorized)
        #expect(uncategorized.totalMinor == 1_000)
        #expect(uncategorized.change == nil)

        let november = F.october.next(in: F.minsk)
        let decrease = engine.summary(for: november, records: F.records, now: F.now)
        #expect(decrease.totalMinor == 7_000)
        #expect(decrease.averagedDayCount == 30)
        #expect(decrease.change == (7_000.0 - 15_000.0) / 15_000.0)
    }

    @Test func emptyData() {
        let summary = engine.summary(for: F.october, records: [], now: F.now)
        #expect(summary.totalMinor == 0 && summary.count == 0 && summary.averagePerDayMinor == 0)
        #expect(summary.change == nil)
        #expect(engine.categoryBreakdown(for: F.october, records: []).isEmpty)
        #expect(engine.topExpenses(for: F.october, records: [], limit: 5).isEmpty)

        let series = engine.timeSeries(for: F.october, records: [])
        #expect(series.buckets.count == 31)
        #expect(series.buckets.allSatisfy { $0.totalMinor == 0 && $0.count == 0 })

        let cumulative = engine.cumulativeComparison(for: F.october, records: [], now: F.now)
        #expect(cumulative.current.count == 8)
        #expect(cumulative.previous.count == 30)
        #expect((cumulative.current + cumulative.previous).allSatisfy { $0.cumulativeMinor == 0 })

        let weekdays = engine.weekdayAverages(for: F.october, records: [], now: F.now)
        #expect(weekdays.count == 7)
        #expect(weekdays.allSatisfy { $0.averageMinor == 0 })
    }

    @Test(arguments: [
        (Int64(10), 4, Int64(3)),
        (Int64(9), 4, Int64(2)),
        (Int64(11), 4, Int64(3)),
        (Int64(1_000), 3, Int64(333)),
        (Int64(-10), 4, Int64(-3)),
        (Int64(5), 0, Int64(0))
    ])
    func divideRoundedHalfAwayFromZero(value: Int64, divisor: Int, expected: Int64) {
        #expect(StatisticsEngine.divideRounded(value, by: divisor) == expected)
    }

    // MARK: - Категории

    @Test func categoryBreakdownSortedWithUncategorizedRow() {
        let rows = engine.categoryBreakdown(for: F.october, records: F.records)
        #expect(rows.map(\.categoryID) == [F.food, F.transport, nil])
        #expect(rows.map(\.totalMinor) == [12_000, 2_000, 1_000])
        #expect(rows.map(\.count) == [3, 1, 1])
        #expect(rows[0].share == 0.8)
        #expect(abs(rows.map(\.share).reduce(0, +) - 1) < 1e-12)
    }

    @Test func categoryBreakdownTiesAreDeterministic() {
        let records = [
            F.record(500, F.now),
            F.record(500, F.now, F.transport),
            F.record(500, F.now, F.food),
            F.record(250, F.now, F.food),
            F.record(250, F.now, F.food)
        ]
        let rows = engine.categoryBreakdown(for: F.october, records: records)
        // Еда: 1000 (3 траты); транспорт и «без категории» по 500 — категория выше.
        #expect(rows.map(\.categoryID) == [F.food, F.transport, nil])
    }

    // MARK: - Временной ряд

    @Test func dailySeriesOfMonthFillsZeros() {
        let series = engine.timeSeries(for: F.october, records: F.records)
        #expect(series.step == .day)
        #expect(series.buckets.count == 31)
        #expect(series.buckets.first?.interval.start == F.date(2026, 10, 1))
        #expect(series.buckets.last?.interval.end == F.date(2026, 11, 1))
        #expect(series.buckets[0].totalMinor == 3_000)
        #expect(series.buckets[4].totalMinor == 2_000)
        #expect(series.buckets[7].totalMinor == 5_000 && series.buckets[7].count == 2)
        #expect(series.buckets[19].totalMinor == 5_000)
        #expect(series.buckets.map(\.totalMinor).reduce(0, +) == 15_000)
    }

    @Test func defaultStepsByPeriodKind() {
        let day = engine.timeSeries(for: .current(.day, now: F.now, calendar: F.minsk), records: F.records)
        #expect(day.step == .hour)
        #expect(day.buckets.count == 24)
        #expect(day.buckets[10].totalMinor == 4_000)
        #expect(day.buckets[20].totalMinor == 1_000)

        let week = engine.timeSeries(for: .current(.week, now: F.now, calendar: F.minsk), records: F.records)
        #expect(week.step == .day)
        #expect(week.buckets.map(\.totalMinor) == [2_000, 0, 0, 5_000, 0, 0, 0])

        let year = engine.timeSeries(for: .current(.year, now: F.now, calendar: F.minsk), records: F.records)
        #expect(year.step == .month)
        #expect(year.buckets.count == 12)
        #expect(year.buckets[8].totalMinor == 12_000)
        #expect(year.buckets[9].totalMinor == 15_000)
        #expect(year.buckets[10].totalMinor == 7_000)
    }

    @Test func customPeriodDefaultSteps() {
        let hours = StatsPeriod.custom(DateInterval(start: F.date(2026, 10, 8, 6), end: F.date(2026, 10, 8, 18)))
        #expect(engine.timeSeries(for: hours, records: []).step == .hour)
        #expect(engine.timeSeries(for: hours, records: []).buckets.count == 12)

        let days = StatsPeriod.custom(DateInterval(start: F.date(2026, 9, 1), end: F.date(2026, 11, 1)))
        #expect(engine.timeSeries(for: days, records: []).step == .day)

        let months = StatsPeriod.custom(DateInterval(start: F.date(2026, 1, 1), end: F.date(2026, 7, 1)))
        let series = engine.timeSeries(for: months, records: [])
        #expect(series.step == .month)
        #expect(series.buckets.count == 6)
    }

    @Test func explicitWeekStepClipsBucketsToPeriod() {
        let series = engine.timeSeries(for: F.october, records: F.records, step: .week)
        #expect(series.step == .week)
        #expect(series.buckets.map(\.interval.start) == [
            F.date(2026, 10, 1), F.date(2026, 10, 5), F.date(2026, 10, 12),
            F.date(2026, 10, 19), F.date(2026, 10, 26)
        ])
        #expect(series.buckets.last?.interval.end == F.date(2026, 11, 1))
        #expect(series.buckets.map(\.totalMinor) == [3_000, 7_000, 0, 5_000, 0])
    }

    @Test func seriesFilterByCategory() {
        let series = engine.timeSeries(for: F.october, records: F.records, filter: .uncategorized)
        #expect(series.buckets.map(\.totalMinor).reduce(0, +) == 1_000)
        #expect(series.buckets[7].totalMinor == 1_000)
    }

    @Test func hourlySeriesAcrossDaylightSaving() {
        let berlin = StatisticsEngine(calendar: F.berlin)
        let autumn = StatsPeriod.current(.day, now: F.date(2026, 10, 25, 12, in: F.berlin), calendar: F.berlin)
        let spring = StatsPeriod.current(.day, now: F.date(2026, 3, 29, 12, in: F.berlin), calendar: F.berlin)
        #expect(berlin.timeSeries(for: autumn, records: []).buckets.count == 25)
        #expect(berlin.timeSeries(for: spring, records: []).buckets.count == 23)

        let march = StatsPeriod.current(.month, now: F.date(2026, 3, 15, in: F.berlin), calendar: F.berlin)
        let daily = berlin.timeSeries(for: march, records: [])
        #expect(daily.buckets.count == 31)
        #expect(daily.buckets[28].interval.duration == 23 * 3600)
        let summary = berlin.summary(for: march, records: [], now: F.now)
        #expect(summary.averagedDayCount == 31)
    }

    // MARK: - Накопительная кривая

    @Test func cumulativeThisMonthVsPrevious() {
        let comparison = engine.cumulativeComparison(for: F.october, records: F.records, now: F.now)
        #expect(comparison.current.map(\.dayNumber) == Array(1...8))
        #expect(comparison.current.map(\.cumulativeMinor) == [3_000, 3_000, 3_000, 3_000, 5_000, 5_000, 5_000, 10_000])
        #expect(comparison.current.last?.date == F.date(2026, 10, 8))

        #expect(comparison.previous.count == 30)
        #expect(comparison.previous[13].cumulativeMinor == 0)
        #expect(comparison.previous[14].cumulativeMinor == 10_000)
        #expect(comparison.previous.last?.cumulativeMinor == 12_000)
        #expect(comparison.previous.first?.date == F.date(2026, 9, 1))
    }

    @Test func cumulativeOfPastPeriodCoversAllDays() {
        let september = F.october.previous(in: F.minsk)
        let comparison = engine.cumulativeComparison(
            for: september, records: F.records, now: F.now, filter: .category(F.food)
        )
        #expect(comparison.current.count == 30)
        #expect(comparison.current.last?.cumulativeMinor == 10_000)
        #expect(comparison.previous.count == 31)
    }

    // MARK: - Дни недели

    @Test func weekdayAveragesOfCurrentMonth() {
        let averages = engine.weekdayAverages(for: F.october, records: F.records, now: F.now)
        #expect(averages.map(\.weekday) == [2, 3, 4, 5, 6, 7, 1])
        // 1–8 октября: два четверга (1 и 8), остальные дни — по одному.
        #expect(averages.map(\.dayCount) == [1, 1, 1, 2, 1, 1, 1])
        let thursday = averages[3]
        #expect(thursday.totalMinor == 8_000)
        #expect(thursday.averageMinor == 4_000)
        #expect(averages[0].averageMinor == 2_000)
        #expect(averages.map(\.totalMinor).reduce(0, +) == 10_000)
    }

    @Test func weekdayAveragesFollowFirstWeekdayAndFilter() {
        let sundayFirst = StatisticsEngine(calendar: F.makeCalendar(timeZone: "Europe/Minsk", firstWeekday: 1))
        let september = F.october.previous(in: F.minsk)
        let averages = sundayFirst.weekdayAverages(
            for: september, records: F.records, now: F.now, filter: .category(F.transport)
        )
        #expect(averages.map(\.weekday) == [1, 2, 3, 4, 5, 6, 7])
        #expect(averages.map(\.dayCount).reduce(0, +) == 30)
        // 30 сентября 2026 — среда; сред в сентябре 5.
        #expect(averages[3].dayCount == 5)
        #expect(averages[3].totalMinor == 2_000)
        #expect(averages[3].averageMinor == 400)
    }

    // MARK: - Топ трат

    @Test func topExpensesSortedAndLimited() {
        let top = engine.topExpenses(for: F.october, records: F.records, limit: 3)
        #expect(top.map(\.amountMinor) == [5_000, 4_000, 3_000])
        #expect(engine.topExpenses(for: F.october, records: F.records, limit: 100).count == 5)
        #expect(engine.topExpenses(for: F.october, records: F.records, limit: 0).isEmpty)
        #expect(engine.topExpenses(for: F.october, records: F.records, limit: -1).isEmpty)

        let food = engine.topExpenses(for: F.october, records: F.records, limit: 10, filter: .category(F.food))
        #expect(food.map(\.amountMinor) == [5_000, 4_000, 3_000])
    }

    @Test func topExpensesTieBreakByLaterDate() {
        let earlier = F.record(900, F.date(2026, 10, 2))
        let later = F.record(900, F.date(2026, 10, 3))
        let top = engine.topExpenses(for: F.october, records: [earlier, later], limit: 2)
        #expect(top == [later, earlier])
    }
}
