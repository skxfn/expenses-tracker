import Foundation
import Testing
@testable import ExpenseCore

/// Ступени шкалы heat для выделения дней в календаре: границы ступени и число дней на каждой.
@Suite struct StatsHeatLevelTests {
    private let scale = StatsHeatScale(thresholds: [2_500, 5_000, 7_500])

    @Test func rangesFollowLevels() {
        #expect(scale.levelCount == 5)
        #expect(scale.range(ofLevel: 0) == .zero)
        #expect(scale.range(ofLevel: 1) == .below(2_500))
        #expect(scale.range(ofLevel: 2) == .between(lower: 2_500, upper: 5_000))
        #expect(scale.range(ofLevel: 3) == .between(lower: 5_000, upper: 7_500))
        #expect(scale.range(ofLevel: 4) == .from(7_500))
        #expect(scale.range(ofLevel: 5) == nil)
        #expect(scale.range(ofLevel: -1) == nil)
    }

    /// Граница ступени — как у `level(forMinor:)`: нижняя включительно, верхняя — нет.
    @Test func rangeMatchesLevelOfAmount() throws {
        for amount: Int64 in [1, 2_499, 2_500, 4_999, 5_000, 7_499, 7_500, 1_000_000] {
            let range = try #require(scale.range(ofLevel: scale.level(forMinor: amount)))
            switch range {
            case .zero: Issue.record("сумма \(amount) > 0 не на ступени 0")
            case .below(let upper): #expect(amount < upper)
            case .between(let lower, let upper): #expect(lower <= amount && amount < upper)
            case .from(let lower): #expect(amount >= lower)
            }
        }
    }

    @Test func singleThresholdHasNoMiddleLevels() {
        let short = StatsHeatScale(thresholds: [1_000])
        #expect(short.levelCount == 3)
        #expect(short.range(ofLevel: 1) == .below(1_000))
        #expect(short.range(ofLevel: 2) == .from(1_000))
    }

    /// Без границ в легенде только «0» (`cal.legend.items`) — других ступеней нет.
    @Test func noThresholdsHasOnlyZero() {
        let empty = StatsHeatScale(thresholds: [])
        #expect(empty.levelCount == 1)
        #expect(empty.range(ofLevel: 0) == .zero)
        #expect(empty.range(ofLevel: 1) == nil)
        #expect(empty.dayCounts([0, 500, 0]) == [2])
    }

    @Test func dayCountsByLevel() {
        let totals: [Int64] = [0, 0, 1_000, 2_500, 4_999, 7_500, 12_000, 0]
        #expect(scale.dayCounts(totals) == [3, 1, 2, 0, 2])
        #expect(scale.dayCounts([]) == [0, 0, 0, 0, 0])
    }
}
