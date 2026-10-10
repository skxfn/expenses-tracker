import Foundation
import Testing
@testable import ExpenseCore

/// Оси графиков статистики, строки тепловой карты года, видимость «Привычек».
@Suite struct StatisticsChartAxesTests {
    private typealias F = StatsFixture

    // MARK: - Подписи оси дней

    @Test func monthLabelsAreEverySeventhDay() {
        // Октябрь, сегодня 8-е (индекс 7): «1, 8, 15, 22, 29».
        #expect(StatsChartAxes.labeledIndices(count: 31, pinned: [7]) == [0, 7, 14, 21, 28])
        #expect(StatsChartAxes.labeledIndices(count: 31) == [0, 7, 14, 21, 28])
    }

    @Test func todayLabelReplacesCloseOnes() {
        // Сегодня 10-е: «8» слишком близко и убирается, «10» подписано.
        #expect(StatsChartAxes.labeledIndices(count: 31, pinned: [9]) == [0, 9, 14, 21, 28])
        // Сегодня 12-е: до «8» и «15» по 4 и 3 дня — обе остаются.
        #expect(StatsChartAxes.labeledIndices(count: 31, pinned: [11]) == [0, 7, 11, 14, 21, 28])
    }

    @Test func paceLabelsEndWithLastDay() {
        // «Темп» за октябрь: «1, 8, 15, 22, 31» — 29 убирается рядом с 31.
        #expect(StatsChartAxes.labeledIndices(count: 31, pinned: [7, 30]) == [0, 7, 14, 21, 30])
    }

    @Test func shortAxesAreFullyLabeled() {
        #expect(StatsChartAxes.labeledIndices(count: 7, pinned: [3]) == Array(0..<7))
        #expect(StatsChartAxes.labeledIndices(count: 3) == [0, 1, 2])
        #expect(StatsChartAxes.labeledIndices(count: 0).isEmpty)
        // Закреплённый индекс вне оси не добавляется.
        #expect(StatsChartAxes.labeledIndices(count: 31, pinned: [40]) == [0, 7, 14, 21, 28])
    }

    // MARK: - Деления оси сумм

    @Test(arguments: [
        (Int64(160_000), [Int64(50_000), 100_000, 150_000]),   // 1 600 → 500, 1 000, 1 500 (макет)
        (3_000, [1_000, 2_000, 3_000]),                         // 30 → 10, 20, 30
        (7_500, [2_000, 4_000, 6_000]),                         // 75 → 20, 40, 60
        (9_000, [2_500, 5_000, 7_500]),                         // 90 → 25, 50, 75 (шаг 20 дал бы 4 деления)
        (250, [100, 200]),                                      // 2,50 → 1, 2
        (99, [])                                                // меньше единицы — без делений
    ] as [(Int64, [Int64])])
    func valueTicksAreRound(maxMinor: Int64, expected: [Int64]) {
        #expect(StatsChartAxes.valueTicks(upTo: maxMinor) == expected)
    }

    @Test func valueTicksNearInt64LimitDoNotOverflow() {
        let ticks = StatsChartAxes.valueTicks(upTo: .max)
        #expect(!ticks.isEmpty && ticks.count <= 3)
        #expect(ticks.allSatisfy { $0 > 0 })
    }

    // MARK: - Тепловая карта года

    @Test func yearDaysAreGroupedByMonth() {
        let months = F.engine.yearDays(forYearContaining: F.now, records: F.records)
        #expect(months.map(\.count) == [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])
        let october = months[9]
        #expect(F.minsk.component(.day, from: october[0].interval.start) == 1)
        #expect(october[0].totalMinor == 3_000)
        #expect(october[7].totalMinor == 5_000)   // 8 октября: 4000 + 1000
        #expect(months[10][0].totalMinor == 7_000) // 1 ноября
        // Фильтр действует на суммы.
        let food = F.engine.yearDays(forYearContaining: F.now, records: F.records, filter: .category(F.food))
        #expect(food[9][7].totalMinor == 4_000)
    }

    // MARK: - Видимость «Привычек»

    @Test func habitsOnlyForMonthAndYear() {
        let engine = F.engine
        #expect(engine.showsHabits(for: F.october))
        #expect(engine.showsHabits(for: .current(.year, now: F.now, calendar: F.minsk)))
        #expect(!engine.showsHabits(for: .current(.week, now: F.now, calendar: F.minsk)))
        #expect(!engine.showsHabits(for: .current(.day, now: F.now, calendar: F.minsk)))
        #expect(!engine.showsHabits(for: .custom(DateInterval(start: F.date(2026, 10, 1), end: F.date(2026, 10, 15)))))
    }
}
