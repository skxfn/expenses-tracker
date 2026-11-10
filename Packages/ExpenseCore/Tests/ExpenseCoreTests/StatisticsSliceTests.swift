import Foundation
import Testing
@testable import ExpenseCore

/// Детализация статистики: выбор категории или подкатегории, срезы трат для списков и журнала, день «Темпа».
@Suite struct StatisticsSliceTests {
    private typealias F = StatsFixture
    private let engine = F.engine

    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    // Продукты с подкатегориями «Супермаркет», «Рынок» (у «Рынка» в октябре трат нет); Кафе без подкатегорий.
    private static let food = id(1), cafe = id(2), market = id(11), bazaar = id(12)

    private static let catalog = CategoryCatalogSnapshot([
        .init(id: food, name: "Продукты", iconName: "basket-fill", tone: .shalfey, subcategoryCount: 2),
        .init(id: market, name: "Супермаркет", iconName: "shopping-cart-1-fill", tone: .shalfey,
              parentID: food, siblingPosition: 0),
        .init(id: bazaar, name: "Рынок", iconName: "apple-fruit-fill", tone: .shalfey,
              parentID: food, siblingPosition: 1),
        .init(id: cafe, name: "Кафе", iconName: "fork-knife-fill", tone: .abrikos)
    ])

    /// Октябрь: супермаркет 3 000 (8-го), продукты без подкатегории 2 000 (5-го), кафе 1 500 и 500 (8-го, 1-го),
    /// без категории 700 (2-го). Порядок — как у ленты: новые выше.
    private static let records: [ExpenseRecord] = [
        ExpenseRecord(id: id(101), amountMinor: 1_500, date: F.date(2026, 10, 8, 13), categoryID: cafe),
        ExpenseRecord(id: id(102), amountMinor: 3_000, date: F.date(2026, 10, 8, 9), categoryID: market, groupID: food),
        ExpenseRecord(id: id(103), amountMinor: 2_000, date: F.date(2026, 10, 5, 18), categoryID: food),
        ExpenseRecord(id: id(104), amountMinor: 700, date: F.date(2026, 10, 2, 12), categoryID: nil),
        ExpenseRecord(id: id(105), amountMinor: 500, date: F.date(2026, 10, 1, 8), categoryID: cafe),
        ExpenseRecord(id: id(106), amountMinor: 900, date: F.date(2026, 9, 30, 20), categoryID: cafe)
    ]

    private var data: CategoryVizData {
        let breakdown = engine.groupBreakdown(for: F.october, records: Self.records, stepRank: Self.catalog.stepRank)
        return CategoryVizData(breakdown: breakdown, catalog: Self.catalog)
    }

    // MARK: - Выбор

    @Test func selectionFilters() {
        #expect(StatsCategorySelection.group(Self.food).filter == .group(Self.food))
        #expect(StatsCategorySelection.uncategorized.filter == .uncategorized)
        #expect(StatsCategorySelection.subcategory(Self.market, groupID: Self.food).filter == .category(Self.market))
        // «Без подкатегории» — траты, записанные прямо в категорию.
        #expect(StatsCategorySelection.unassigned(groupID: Self.food).filter == .category(Self.food))
    }

    @Test func selectionFromVisualization() throws {
        let data = data
        let food = try #require(data.group(Self.food))
        let uncategorized = try #require(data.group(nil))
        #expect(StatsCategorySelection(food) == .group(Self.food))
        #expect(StatsCategorySelection(uncategorized) == .uncategorized)

        let parts = food.parts
        #expect(parts.compactMap { StatsCategorySelection($0, of: food) }
            == [.subcategory(Self.market, groupID: Self.food), .unassigned(groupID: Self.food)])
        #expect(StatsCategorySelection(parts[0], of: uncategorized) == nil)

        let sub = StatsCategorySelection.subcategory(Self.market, groupID: Self.food)
        #expect(sub.isPart && sub.whole == .group(Self.food) && sub.groupID == Self.food)
        #expect(sub.isSelected(parts[0]) && !sub.isSelected(parts[1]))
        #expect(StatsCategorySelection.unassigned(groupID: Self.food).isSelected(parts[1]))
    }

    @Test func tapsToggleSelection() throws {
        let data = data
        let food = try #require(data.group(Self.food))
        let cafe = try #require(data.group(Self.cafe))
        let market = food.parts[0], unassigned = food.parts[1]
        typealias S = StatsCategorySelection

        #expect(S.toggling(cafe, from: nil) == .group(Self.cafe))
        #expect(S.toggling(cafe, from: .group(Self.food)) == .group(Self.cafe))
        #expect(S.toggling(cafe, from: .group(Self.cafe)) == nil)
        // Строка категории при выбранной подкатегории сворачивает к обзору.
        #expect(S.toggling(food, from: .subcategory(Self.market, groupID: Self.food)) == nil)

        #expect(S.toggling(market, of: food, from: .group(Self.food)) == .subcategory(Self.market, groupID: Self.food))
        #expect(S.toggling(unassigned, of: food, from: .subcategory(Self.market, groupID: Self.food))
            == .unassigned(groupID: Self.food))
        #expect(S.toggling(market, of: food, from: .subcategory(Self.market, groupID: Self.food)) == .group(Self.food))
    }

    @Test func selectionResolvesAgainstPeriod() {
        let data = data
        // Любая категория выбирается, в том числе без подкатегорий и «Без категории».
        #expect(data.resolved(.group(Self.cafe)) == .group(Self.cafe))
        #expect(data.group(for: .group(Self.cafe))?.isExpandable == false)
        #expect(data.resolved(.uncategorized) == .uncategorized)
        // Подкатегория без трат в периоде — выбрана её категория целиком.
        #expect(data.resolved(.subcategory(Self.bazaar, groupID: Self.food)) == .group(Self.food))
        #expect(data.part(for: .subcategory(Self.bazaar, groupID: Self.food)) == nil)
        #expect(data.part(for: .subcategory(Self.market, groupID: Self.food))?.totalMinor == 3_000)
        #expect(data.part(for: .unassigned(groupID: Self.food))?.totalMinor == 2_000)
        // Категории нет в периоде — выбора нет.
        #expect(data.resolved(.group(Self.bazaar)) == nil)
        #expect(data.resolved(nil) == nil)
    }

    // MARK: - Срезы и дни

    @Test func journalOfCategoryByDays() {
        let slice = engine.slice(period: F.october, filter: .group(Self.food))
        let days = engine.expenseDays(in: slice, records: Self.records)
        #expect(days.map(\.day) == [F.date(2026, 10, 8), F.date(2026, 10, 5)])
        #expect(days.map(\.totalMinor) == [3_000, 2_000])
        #expect(days.map(\.expenseIDs) == [[Self.id(102)], [Self.id(103)]])
    }

    @Test func daysKeepFeedOrderAndSortDays() {
        // Вход не по порядку дней: дни всё равно от новых к старым, траты дня — в порядке входа.
        let shuffled = [Self.records[4], Self.records[0], Self.records[3], Self.records[1]]
        let days = engine.expenseDays(in: engine.slice(period: F.october, filter: .all), records: shuffled)
        #expect(days.map(\.day) == [F.date(2026, 10, 8), F.date(2026, 10, 2), F.date(2026, 10, 1)])
        #expect(days[0].expenseIDs == [Self.id(101), Self.id(102)])
        #expect(days[0].totalMinor == 4_500)
    }

    @Test func subcategoryUnassignedAndUncategorizedSlices() {
        func ids(_ filter: StatsCategoryFilter) -> [UUID] {
            engine.expenseDays(in: engine.slice(period: F.october, filter: filter), records: Self.records)
                .flatMap(\.expenseIDs)
        }
        #expect(ids(StatsCategorySelection.subcategory(Self.market, groupID: Self.food).filter) == [Self.id(102)])
        #expect(ids(StatsCategorySelection.unassigned(groupID: Self.food).filter) == [Self.id(103)])
        #expect(ids(.uncategorized) == [Self.id(104)])
        // Сентябрьская трата кафе в октябрьский журнал не попадает.
        #expect(ids(.group(Self.cafe)) == [Self.id(101), Self.id(105)])
    }

    @Test func bucketAndDaySlicesAreHalfOpen() throws {
        let series = engine.timeSeries(for: F.october, records: Self.records, step: .day)
        let first = try #require(series.buckets.first)
        let slice = engine.slice(bucket: first, step: .day, filter: .all)
        #expect(slice.scope == .bucket(.day))
        #expect(engine.expenseDays(in: slice, records: Self.records).flatMap(\.expenseIDs) == [Self.id(105)])
        // День «Темпа» — календарный день целиком; полночь следующего дня в него не входит.
        let day = engine.slice(dayContaining: F.date(2026, 10, 8, 23), filter: .group(Self.cafe))
        #expect(day.interval == DateInterval(start: F.date(2026, 10, 8), end: F.date(2026, 10, 9)))
        #expect(day.contains(ExpenseRecord(amountMinor: 1, date: F.date(2026, 10, 9), categoryID: Self.cafe),
                             calendar: F.minsk) == false)
    }

    @Test func weekdaySliceMatchesHabits() throws {
        // Четверги октября по сегодня (8 октября): 1-е и 8-е.
        let slice = engine.slice(weekday: 5, period: F.october, now: F.now, filter: .all)
        #expect(slice.interval.end == F.date(2026, 10, 9))
        let ids = engine.expenseDays(in: slice, records: Self.records).flatMap(\.expenseIDs)
        #expect(ids == [Self.id(101), Self.id(102), Self.id(105)])

        let averages = engine.weekdayAverages(for: F.october, records: Self.records, now: F.now)
        let thursday = try #require(averages.first { $0.weekday == 5 })
        #expect(thursday.count == ids.count)
        #expect(thursday.totalMinor == 5_000)
    }

    @Test func previewKeepsWholeDays() {
        let days = [
            StatsExpenseDay(day: F.date(2026, 10, 8), totalMinor: 3, expenseIDs: [Self.id(1), Self.id(2), Self.id(3)]),
            StatsExpenseDay(day: F.date(2026, 10, 7), totalMinor: 2, expenseIDs: [Self.id(4), Self.id(5)]),
            StatsExpenseDay(day: F.date(2026, 10, 6), totalMinor: 1, expenseIDs: [Self.id(6)])
        ]
        #expect(StatsExpenseDay.preview(days, rowLimit: 4).count == 2)
        #expect(StatsExpenseDay.preview(days, rowLimit: 3).count == 1)
        // Первый день — целиком, даже если он длиннее предела.
        #expect(StatsExpenseDay.preview(days, rowLimit: 1).map(\.expenseIDs.count) == [3])
        #expect(StatsExpenseDay.preview([], rowLimit: 4).isEmpty)
    }

    // MARK: - День «Темпа»

    @Test func paceDayComparesSameDayNumber() throws {
        let comparison = engine.cumulativeComparison(for: F.october, records: Self.records, now: F.now)
        let day1 = try #require(comparison.day(1))
        #expect(day1.current.cumulativeMinor == 500)
        #expect(day1.dayMinor == 500)
        #expect(day1.previous?.cumulativeMinor == 0)
        #expect(day1.differenceMinor == nil && day1.trend == nil)

        let day8 = try #require(comparison.day(8))
        #expect(day8.current.cumulativeMinor == 7_700)
        #expect(day8.dayMinor == 4_500)
        #expect(comparison.day(9) == nil)
        #expect(comparison.day(0) == nil)
    }

    @Test func paceDayTrend() {
        func day(_ current: Int64, _ previous: Int64?) -> StatsPaceDay {
            StatsPaceDay(
                current: StatsCumulativePoint(dayNumber: 3, date: F.now, cumulativeMinor: current),
                previous: previous.map { StatsCumulativePoint(dayNumber: 3, date: F.now, cumulativeMinor: $0) },
                dayMinor: 0
            )
        }
        #expect(day(1_200, 1_000).trend == .more)
        #expect(day(1_200, 1_000).differenceMinor == 200)
        #expect(day(800, 1_000).trend == .less)
        #expect(day(1_005, 1_000).trend == .same)
        #expect(day(1_000, nil).trend == nil)
    }
}
