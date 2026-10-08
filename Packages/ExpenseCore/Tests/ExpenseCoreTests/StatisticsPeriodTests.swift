import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

@Suite struct StatisticsPeriodTests {
    private typealias F = StatsFixture

    @Test func currentPeriodsAroundNow() {
        let cases: [(StatsPeriodKind, Date, Date)] = [
            (.day, F.date(2026, 10, 8), F.date(2026, 10, 9)),
            (.week, F.date(2026, 10, 5), F.date(2026, 10, 12)),
            (.month, F.date(2026, 10, 1), F.date(2026, 11, 1)),
            (.year, F.date(2026, 1, 1), F.date(2027, 1, 1))
        ]
        for (kind, start, end) in cases {
            let period = StatsPeriod.current(kind, now: F.now, calendar: F.minsk)
            #expect(period.kind == kind)
            #expect(period.interval == DateInterval(start: start, end: end), "\(kind)")
        }
    }

    @Test func weekStartsAtCalendarFirstWeekday() {
        let sundayFirst = F.makeCalendar(timeZone: "Europe/Minsk", firstWeekday: 1)
        let week = StatsPeriod.current(.week, now: F.now, calendar: sundayFirst)
        #expect(week.interval.start == F.date(2026, 10, 4))
        #expect(week.interval.end == F.date(2026, 10, 11))
    }

    @Test func containsIsHalfOpen() {
        let october = F.october
        #expect(october.contains(F.date(2026, 10, 1)))
        #expect(october.contains(F.date(2026, 10, 31, 23, 59, 59)))
        #expect(!october.contains(F.date(2026, 11, 1)))
        #expect(!october.contains(F.date(2026, 9, 30, 23, 59, 59)))
    }

    @Test(arguments: StatsPeriodKind.allCases)
    func previousAndNextAreAdjacentAndInverse(kind: StatsPeriodKind) {
        let period = StatsPeriod.current(kind, now: F.now, calendar: F.minsk)
        let previous = period.previous(in: F.minsk)
        let next = period.next(in: F.minsk)
        #expect(previous.kind == kind)
        #expect(previous.interval.end == period.interval.start)
        #expect(next.interval.start == period.interval.end)
        #expect(previous.next(in: F.minsk) == period)
        #expect(next.previous(in: F.minsk) == period)
    }

    @Test func monthNavigationAcrossYearAndShortMonths() {
        let january = StatsPeriod.current(.month, now: F.date(2026, 1, 15), calendar: F.minsk)
        #expect(january.previous(in: F.minsk).interval.start == F.date(2025, 12, 1))

        let december = StatsPeriod.current(.month, now: F.date(2026, 12, 31, 23, 59), calendar: F.minsk)
        #expect(december.next(in: F.minsk).interval == DateInterval(start: F.date(2027, 1, 1), end: F.date(2027, 2, 1)))

        let march31 = StatsPeriod.current(.month, now: F.date(2026, 3, 31), calendar: F.minsk)
        #expect(march31.previous(in: F.minsk).interval == DateInterval(start: F.date(2026, 2, 1), end: F.date(2026, 3, 1)))

        let leapMarch = StatsPeriod.current(.month, now: F.date(2028, 3, 31), calendar: F.minsk)
        #expect(leapMarch.previous(in: F.minsk).interval.end == F.date(2028, 3, 1))
        #expect(leapMarch.previous(in: F.minsk).interval.start == F.date(2028, 2, 1))
    }

    @Test func weekNavigationAcrossYear() {
        // Неделя 28.12.2026 – 03.01.2027 (пн–вс).
        let week = StatsPeriod.current(.week, now: F.date(2027, 1, 2), calendar: F.minsk)
        #expect(week.interval == DateInterval(start: F.date(2026, 12, 28), end: F.date(2027, 1, 4)))
        #expect(week.next(in: F.minsk).interval.start == F.date(2027, 1, 4))
    }

    @Test func customPeriodShiftsBySameLength() {
        let custom = StatsPeriod.custom(DateInterval(start: F.date(2026, 10, 1), end: F.date(2026, 10, 8)))
        #expect(custom.kind == nil)
        #expect(custom.previous(in: F.minsk).interval == DateInterval(start: F.date(2026, 9, 24), end: F.date(2026, 10, 1)))
        #expect(custom.next(in: F.minsk).interval == DateInterval(start: F.date(2026, 10, 8), end: F.date(2026, 10, 15)))
        #expect(custom.previous(in: F.minsk).kind == nil)
    }

    // MARK: - DST

    @Test func daysAroundDaylightSavingTransitions() {
        let berlin = F.berlin
        let springDay = StatsPeriod.current(.day, now: F.date(2026, 3, 29, 12, in: berlin), calendar: berlin)
        #expect(springDay.interval.duration == 23 * 3600)
        #expect(springDay.next(in: berlin).interval.start == F.date(2026, 3, 30, in: berlin))
        #expect(springDay.previous(in: berlin).interval.start == F.date(2026, 3, 28, in: berlin))

        let autumnDay = StatsPeriod.current(.day, now: F.date(2026, 10, 25, 12, in: berlin), calendar: berlin)
        #expect(autumnDay.interval.duration == 25 * 3600)
        #expect(autumnDay.next(in: berlin).interval.start == F.date(2026, 10, 26, in: berlin))
    }

    @Test func weekAndCustomAcrossSpringTransition() {
        let berlin = F.berlin
        let weekAfter = StatsPeriod.current(.week, now: F.date(2026, 4, 1, in: berlin), calendar: berlin)
        let weekWithTransition = weekAfter.previous(in: berlin)
        #expect(weekWithTransition.interval.start == F.date(2026, 3, 23, in: berlin))
        #expect(weekWithTransition.interval.duration == 7 * 24 * 3600 - 3600)

        // Сдвиг произвольного интервала идёт по календарным дням: полночь остаётся полночью.
        let custom = StatsPeriod.custom(DateInterval(
            start: F.date(2026, 3, 30, in: berlin),
            end: F.date(2026, 4, 6, in: berlin)
        ))
        #expect(custom.previous(in: berlin).interval == DateInterval(
            start: F.date(2026, 3, 23, in: berlin),
            end: F.date(2026, 3, 30, in: berlin)
        ))
    }

    // MARK: - ExpenseRecord

    @Test func recordFromSwiftDataExpense() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: ExpenseMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let category = ExpenseCategory(name: "Еда", iconName: "cart", colorHex: "#34C759", sortOrder: 0)
        let expense = Expense(amountMinor: 1_250, date: F.now, category: category)
        let orphan = Expense(amountMinor: 99, date: F.now, category: nil)
        context.insert(category)
        context.insert(expense)
        context.insert(orphan)

        let record = ExpenseRecord(expense)
        #expect(record == ExpenseRecord(id: expense.id, amountMinor: 1_250, date: F.now, categoryID: category.id))
        #expect(ExpenseRecord(orphan).categoryID == nil)
    }

    @Test func categoryFilterMatches() {
        let food = F.record(1, F.now, F.food)
        let none = F.record(1, F.now)
        #expect(StatsCategoryFilter.all.matches(food) && StatsCategoryFilter.all.matches(none))
        #expect(StatsCategoryFilter.category(F.food).matches(food))
        #expect(!StatsCategoryFilter.category(F.food).matches(none))
        #expect(!StatsCategoryFilter.category(F.transport).matches(food))
        #expect(StatsCategoryFilter.uncategorized.matches(none))
        #expect(!StatsCategoryFilter.uncategorized.matches(food))
    }
}
