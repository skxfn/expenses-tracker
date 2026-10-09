import Foundation
import Testing
@testable import ExpenseCore

/// Темп и прогноз, «Привычки», шкала heat, видимость блоков.
@Suite struct StatisticsInsightsTests {
    private typealias F = StatsFixture
    private let engine = F.engine

    private var week: StatsPeriod { .current(.week, now: F.now, calendar: F.minsk) }
    private var year: StatsPeriod { .current(.year, now: F.now, calendar: F.minsk) }
    private var today: StatsPeriod { .current(.day, now: F.now, calendar: F.minsk) }

    // MARK: - Видимость блоков

    @Test func paceAndHourlyVisibility() {
        #expect(engine.showsPace(for: week) && engine.showsPace(for: F.october) && engine.showsPace(for: year))
        #expect(!engine.showsPace(for: today))
        #expect(!engine.showsPace(for: .custom(DateInterval(start: F.date(2026, 10, 1), end: F.date(2026, 10, 5)))))

        #expect(engine.showsHourly(for: today, now: F.now))
        #expect(!engine.showsHourly(for: today.previous(in: F.minsk), now: F.now))
        #expect(!engine.showsHourly(for: F.october, now: F.now))
    }

    // MARK: - Прогноз

    @Test func forecastOfCurrentPeriods() throws {
        // 1–8 октября: 3000 + 2000 + 4000 + 1000 (сегодня вечером) = 10 000; трата 20 октября не в счёт.
        let month = try #require(engine.forecast(for: F.october, records: F.records, now: F.now))
        #expect(month.elapsedDayCount == 8)
        #expect(month.dayCount == 31)
        #expect(month.projectedMinor == 38_750)
        #expect(month.roundedMinor == 39_000)

        // Неделя 5–11 октября, прошло 4 дня: 2000 + 4000 + 1000.
        let weekly = try #require(engine.forecast(for: week, records: F.records, now: F.now))
        #expect(weekly.projectedMinor == 12_250)

        // Год: 22 000 за 281 день × 365 = 28 576,51 → 28 577.
        let yearly = try #require(engine.forecast(for: year, records: F.records, now: F.now))
        #expect(yearly.elapsedDayCount == 281)
        #expect(yearly.projectedMinor == 28_577)
    }

    @Test func noForecastForPastDayAndCustom() {
        #expect(engine.forecast(for: F.october.previous(in: F.minsk), records: F.records, now: F.now) == nil)
        #expect(engine.forecast(for: today, records: F.records, now: F.now) == nil)
        let custom = StatsPeriod.custom(DateInterval(start: F.date(2026, 10, 1), end: F.date(2026, 10, 15)))
        #expect(engine.forecast(for: custom, records: F.records, now: F.now) == nil)
    }

    @Test(arguments: [
        (Int64(158_000), Int64(160_000)),  // 1 580 → 1 600
        (8_745, 8_700),                    // 87,45 → 87
        (9_960, 10_000),                   // 99,60 → 100
        (74_240, 74_000),                  // 742,40 → 740
        (123_456_789, 120_000_000),        // 1 234 567,89 → 1 200 000
        (49, 0),
        (0, 0)
    ])
    func significantDigitsRounding(minor: Int64, expected: Int64) {
        #expect(Money.roundedToSignificantDigits(minor, digits: 2) == expected)
    }

    @Test func roundingNearInt64LimitDoesNotOverflow() {
        let rounded = Money.roundedToSignificantDigits(.max, digits: 2)
        #expect(rounded > 0 && rounded <= .max)
        #expect(Money.roundedToWholeUnits(.max) == 9_223_372_036_854_775_800)
        #expect(Money.roundedToWholeUnits(74_250) == 74_300)
    }

    // MARK: - Достаточно ли данных

    @Test func paceNeedsThreeDaysAndThreeExpenses() {
        let three = [F.record(100, F.date(2026, 10, 1)), F.record(100, F.date(2026, 10, 2)), F.record(100, F.date(2026, 10, 2))]
        #expect(!engine.hasEnoughDataForPace(for: F.october, records: three, now: F.date(2026, 10, 2, 12)))
        #expect(engine.hasEnoughDataForPace(for: F.october, records: three, now: F.date(2026, 10, 3, 12)))
        #expect(!engine.hasEnoughDataForPace(for: F.october, records: Array(three.prefix(2)), now: F.now))
        #expect(!engine.hasEnoughDataForPace(for: F.october, records: three, now: F.now, filter: .category(F.food)))
    }

    @Test func habitsNeedSevenSpendingDays() {
        let sixDays = (1...6).map { F.record(100, F.date(2026, 10, $0, 12)) } + [F.record(100, F.date(2026, 10, 6, 13))]
        #expect(!engine.hasEnoughDataForHabits(for: F.october, records: sixDays, now: F.now))
        let sevenDays = sixDays + [F.record(100, F.date(2026, 10, 7))]
        #expect(engine.hasEnoughDataForHabits(for: F.october, records: sevenDays, now: F.now))
        // Будущие траты не в счёт.
        let future = sixDays + [F.record(100, F.date(2026, 10, 20))]
        #expect(!engine.hasEnoughDataForHabits(for: F.october, records: future, now: F.now))
    }

    // MARK: - Привычки

    /// Прошедшая неделя 28 сен (пн) – 4 окт (вс).
    private var pastWeek: StatsPeriod { week.previous(in: F.minsk) }

    private func habits(_ amounts: [Int: Int64]) -> StatsHabits {
        // Ключ — смещение от понедельника 28 сентября.
        let monday = F.date(2026, 9, 28, 12)
        let records = amounts.map { offset, amount in
            F.record(amount, F.minsk.date(byAdding: .day, value: offset, to: monday)!)
        }
        return engine.habits(for: pastWeek, records: records, now: F.now)
    }

    @Test func peakWeekdayAndWeekdaysLead() {
        let result = habits([0: 1_000, 4: 5_000, 5: 2_000])
        #expect(result.averages.count == 7)
        #expect(result.peakWeekday == 6) // пятница
        // Будни 6000 / 5 = 1200, выходные 2000 / 2 = 1000: разница 200 ≥ 10 % от 1200.
        #expect(result.split == .weekdays)
    }

    @Test func weekendLeadsAndAlmostEven() {
        #expect(habits([0: 1_000, 5: 3_000]).split == .weekend)
        // Будни по 1000, выходные по 950: разница 50 < 100.
        #expect(habits([0: 1_000, 1: 1_000, 2: 1_000, 3: 1_000, 4: 1_000, 5: 950, 6: 950]).split == .even)
        // Ровно 10 % — уже не «почти поровну».
        #expect(habits([0: 1_000, 1: 1_000, 2: 1_000, 3: 1_000, 4: 1_000, 5: 900, 6: 900]).split == .weekdays)
    }

    @Test func peakTieTakesFirstWeekdayAndEmptyHasNoPeak() {
        #expect(habits([1: 500, 3: 500]).peakWeekday == 3) // вторник раньше четверга
        let empty = habits([:])
        #expect(empty.peakWeekday == nil)
        #expect(empty.split == .even)
    }

    @Test func splitUnknownWithoutWeekendDaysYet() {
        // Идущая неделя, сегодня четверг: выходных ещё не было.
        #expect(engine.habits(for: week, records: F.records, now: F.now).split == nil)
    }

    // MARK: - Шкала heat и день с максимумом

    @Test func heatScaleFromRoundedQuartiles() throws {
        let amounts: [Int64] = [500, 1_000, 1_500, 2_000, 2_340, 3_000, 4_800, 6_000, 7_300, 10_000]
        let records = amounts.enumerated().map { day, amount in F.record(amount, F.date(2026, 3, day + 1, 12)) }
            + [F.record(99_999, F.date(2025, 12, 31, 12))] // другой год
        let scale = try #require(engine.heatScale(forYearContaining: F.now, records: records))
        // Квартили (ближайший ранг) 15; 23,40; 60 → 15, 25, 60.
        #expect(scale.thresholds == [1_500, 2_500, 6_000])
        #expect(scale.level(forMinor: 0) == 0)
        #expect(scale.level(forMinor: 1_499) == 1)
        #expect(scale.level(forMinor: 1_500) == 2)
        #expect(scale.level(forMinor: 2_500) == 3)
        #expect(scale.level(forMinor: 6_000) == 4)
        #expect(scale.level(forMinor: 1_000_000) == 4)
    }

    @Test func heatScaleKeepsThresholdsIncreasing() throws {
        let same = (1...5).map { F.record(2_340, F.date(2026, 5, $0)) }
        #expect(try #require(engine.heatScale(forYearContaining: F.now, records: same)).thresholds == [2_500, 3_000, 3_500])

        let tiny = [F.record(40, F.date(2026, 5, 1))]
        #expect(try #require(engine.heatScale(forYearContaining: F.now, records: tiny)).thresholds == [100, 200, 300])

        #expect(engine.heatScale(forYearContaining: F.now, records: []) == nil)
        #expect(engine.heatScale(forYearContaining: F.now, records: F.records, filter: .category(UUID())) == nil)
    }

    @Test(arguments: [
        (Int64(2_340), Int64(2_500)),
        (4_800, 5_000),
        (7_300, 7_500),
        (340, 300),
        (40, 100),
        (13_700, 15_000),
        (26_000, 25_000),
        (9_700, 9_500)
    ])
    func niceNumbers(minor: Int64, expected: Int64) {
        #expect(StatisticsEngine.roundedToNiceNumber(minor) == expected)
    }

    @Test func peakDayOfSeries() {
        let series = engine.timeSeries(for: F.october, records: F.records)
        // 8 и 20 октября — по 5000: берётся более ранний.
        #expect(series.peak?.interval.start == F.date(2026, 10, 8))
        #expect(engine.timeSeries(for: F.october, records: []).peak == nil)
    }
}
