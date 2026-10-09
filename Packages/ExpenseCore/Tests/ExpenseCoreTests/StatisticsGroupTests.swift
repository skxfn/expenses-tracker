import Foundation
import Testing
@testable import ExpenseCore

/// Разбивка по категориям с подкатегориями, порядок для кругов и «Ещё N».
@Suite struct StatisticsGroupTests {
    private typealias F = StatsFixture
    private let engine = F.engine

    private static let bread = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private static let milk = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

    private func sub(_ amount: Int64, _ subcategory: UUID, _ group: UUID = F.food) -> ExpenseRecord {
        ExpenseRecord(amountMinor: amount, date: F.now, categoryID: subcategory, groupID: group)
    }

    /// Продукты: хлеб 300, молоко 500, без подкатегории 200; транспорт 900; без категории 100.
    private var records: [ExpenseRecord] {
        [
            sub(300, Self.bread),
            sub(500, Self.milk),
            F.record(200, F.now, F.food),
            F.record(900, F.now, F.transport),
            F.record(100, F.now),
            F.record(7_000, F.date(2026, 11, 1), F.food) // вне октября
        ]
    }

    private func group(
        _ id: UUID?, total: Int64, share: Double = 0.1, subcategories: [StatsCategoryShare] = []
    ) -> StatsGroupShare {
        StatsGroupShare(
            groupID: id, totalMinor: total, count: 1, share: share,
            subcategories: subcategories, unassignedMinor: total, unassignedCount: 1
        )
    }

    @Test func breakdownGroupsSubcategoriesAndUnassigned() {
        let rows = engine.groupBreakdown(for: F.october, records: records)
        #expect(rows.map(\.groupID) == [F.food, F.transport, nil])
        #expect(rows.map(\.totalMinor) == [1_000, 900, 100])
        #expect(rows.map(\.count) == [3, 1, 1])
        #expect(rows[0].share == 0.5)
        #expect(abs(rows.map(\.share).reduce(0, +) - 1) < 1e-12)

        let food = rows[0]
        // Без рангов ступеней — по сумме; доля — от итога категории.
        #expect(food.subcategories.map(\.categoryID) == [Self.milk, Self.bread])
        #expect(food.subcategories.map(\.share) == [0.5, 0.3])
        #expect(food.unassignedMinor == 200)
        #expect(food.unassignedCount == 1)
        #expect(food.unassignedShare == 0.2)

        #expect(rows[1].subcategories.isEmpty)
        #expect(rows[1].unassignedMinor == 900)
        #expect(rows[2].unassignedMinor == 100)
    }

    @Test func subcategoriesFollowStepRank() {
        let rows = engine.groupBreakdown(
            for: F.october, records: records, stepRank: [Self.bread: 0, Self.milk: 1]
        )
        #expect(rows[0].subcategories.map(\.categoryID) == [Self.bread, Self.milk])

        // Подкатегория без ранга — после ранжированных.
        let partial = engine.groupBreakdown(for: F.october, records: records, stepRank: [Self.bread: 4])
        #expect(partial[0].subcategories.map(\.categoryID) == [Self.bread, Self.milk])
    }

    @Test func uncategorizedIsAlwaysLast() {
        let rows = engine.groupBreakdown(for: F.october, records: records + [F.record(50_000, F.now)])
        #expect(rows.last?.groupID == nil)
        #expect(rows.last?.totalMinor == 50_100)
        #expect(engine.groupBreakdown(for: F.october, records: []).isEmpty)
    }

    @Test func groupFilterIncludesSubcategories() {
        let food = engine.summary(for: F.october, records: records, now: F.now, filter: .group(F.food))
        #expect(food.totalMinor == 1_000)
        let direct = engine.summary(for: F.october, records: records, now: F.now, filter: .category(F.food))
        #expect(direct.totalMinor == 200)
    }

    @Test func hueOrderWithTiesUnknownAndUncategorized() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let groups = [group(a, total: 500), group(b, total: 400), group(c, total: 300),
                      group(d, total: 200), group(nil, total: 1_000)]
        // b и c одного тона — по сумме; у d тона нет.
        let ordered = StatisticsEngine.orderedByHue(groups, hueRank: [a: 9, b: 2, c: 2])
        #expect(ordered.map(\.groupID) == [b, c, a, d, nil])
    }

    @Test func foldSmallGroupsOnlyWhenThereAreTwo() {
        let big = UUID(), medium = UUID(), small1 = UUID(), small2 = UUID()
        let groups = [group(big, total: 600, share: 0.6), group(small1, total: 20, share: 0.02),
                      group(medium, total: 340, share: 0.34), group(small2, total: 29, share: 0.029),
                      group(nil, total: 11, share: 0.011)]
        let folded = StatisticsEngine.fold(groups)
        #expect(folded.visible.map(\.groupID) == [big, medium, nil])
        #expect(folded.folded.map(\.groupID) == [small1, small2])
        #expect(folded.foldedTotalMinor == 49)
        #expect(abs(folded.foldedShare - 0.049) < 1e-12)

        let single = StatisticsEngine.fold(Array(groups.prefix(3)) + [group(nil, total: 1, share: 0.001)])
        #expect(single.folded.isEmpty)
        #expect(single.visible.count == 4)

        // Порог строгий: ровно 3% не сворачивается.
        let edge = StatisticsEngine.fold([group(UUID(), total: 3, share: 0.03), group(UUID(), total: 3, share: 0.03)])
        #expect(edge.folded.isEmpty)
    }
}
