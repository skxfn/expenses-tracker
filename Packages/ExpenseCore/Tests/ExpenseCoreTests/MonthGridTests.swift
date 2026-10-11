import Foundation
import Testing
@testable import ExpenseCore

/// Раскладка месяца календаря по неделям.
@Suite struct MonthGridTests {
    private typealias F = StatsFixture

    @Test func octoberStartsOnThursdayWithMondayFirst() {
        let grid = MonthGrid(containing: F.now, calendar: F.minsk)
        #expect(grid.start == F.date(2026, 10, 1))
        #expect(grid.days.count == 31)
        #expect(grid.weekdays == [2, 3, 4, 5, 6, 7, 1])
        #expect(grid.weeks.count == 5)
        #expect(grid.weeks.allSatisfy { $0.count == 7 })
        // 1 октября 2026 — четверг: три пустых места перед ним.
        #expect(grid.weeks[0].prefix(3).allSatisfy { $0 == nil })
        #expect(grid.weeks[0][3] == F.date(2026, 10, 1))
        // 31 октября — суббота, после неё одно пустое место.
        #expect(grid.weeks[4][5] == F.date(2026, 10, 31))
        #expect(grid.weeks[4][6] == nil)
        #expect(grid.weeks.joined().compactMap { $0 } == grid.days)
    }

    @Test func sundayFirstCalendarShiftsColumns() {
        let sundayFirst = F.makeCalendar(timeZone: "Europe/Minsk", firstWeekday: 1)
        let grid = MonthGrid(containing: F.now, calendar: sundayFirst)
        #expect(grid.weekdays == [1, 2, 3, 4, 5, 6, 7])
        #expect(grid.weeks[0].prefix(4).allSatisfy { $0 == nil })
        #expect(grid.weeks[0][4] == F.date(2026, 10, 1, in: sundayFirst))
        #expect(grid.weeks.last?.last == F.date(2026, 10, 31, in: sundayFirst))
    }

    @Test func sixWeekMonthAndExactFourWeeks() {
        // Август 2026: 1-е — суббота, 31 день → 6 недель с понедельника.
        let august = MonthGrid(containing: F.date(2026, 8, 15), calendar: F.minsk)
        #expect(august.weeks.count == 6)
        // Февраль 2027: 1-е — понедельник, 28 дней → ровно 4 недели без пустых мест.
        let february = MonthGrid(containing: F.date(2027, 2, 10), calendar: F.minsk)
        #expect(february.weeks.count == 4)
        #expect(february.weeks.joined().allSatisfy { $0 != nil })
    }

    @Test func daysAreStartsOfDaysAcrossDaylightSaving() {
        let grid = MonthGrid(containing: F.date(2026, 10, 15, in: F.berlin), calendar: F.berlin)
        #expect(grid.days.count == 31)
        #expect(grid.days.allSatisfy { F.berlin.startOfDay(for: $0) == $0 })
        #expect(grid.days.last == F.date(2026, 10, 31, in: F.berlin))
    }

    @Test func previousAndNextCrossYear() {
        let january = MonthGrid(containing: F.date(2027, 1, 20), calendar: F.minsk)
        #expect(january.previous().start == F.date(2026, 12, 1))
        #expect(january.previous().next() == january)
        #expect(january.contains(F.date(2027, 1, 31, 23, 59)))
        #expect(!january.contains(F.date(2027, 2, 1)))
    }

    @Test func matchingDayClampsToMonthLengthAndToday() {
        let september = MonthGrid(containing: F.date(2026, 9, 1), calendar: F.minsk)
        // 31 октября → 30 сентября.
        #expect(september.day(matching: F.date(2026, 10, 31), notAfter: F.now) == F.date(2026, 9, 30))
        let october = MonthGrid(containing: F.now, calendar: F.minsk)
        // 20 сентября → 20 октября ещё не наступило → сегодня (8 октября).
        #expect(october.day(matching: F.date(2026, 9, 20), notAfter: F.now) == F.date(2026, 10, 8))
        #expect(october.day(matching: F.date(2026, 9, 3), notAfter: F.now) == F.date(2026, 10, 3))
    }

    // MARK: Смена суток при открытом календаре

    @Test func rolloverWithinSameDayChangesNothing() {
        let october = MonthGrid(containing: F.now, calendar: F.minsk)
        let rolled = october.rolledOver(selected: F.date(2026, 10, 3), from: F.now, to: F.date(2026, 10, 8, 23, 59))
        #expect(rolled.month == october)
        #expect(rolled.selected == F.date(2026, 10, 3))
    }

    @Test func rolloverMovesSelectedTodayToNewToday() {
        let october = MonthGrid(containing: F.now, calendar: F.minsk)
        let rolled = october.rolledOver(selected: F.date(2026, 10, 8), from: F.now, to: F.date(2026, 10, 9, 0, 1))
        #expect(rolled.month == october)
        #expect(rolled.selected == F.date(2026, 10, 9))
    }

    @Test func rolloverKeepsOtherSelectedDay() {
        let october = MonthGrid(containing: F.now, calendar: F.minsk)
        let rolled = october.rolledOver(selected: F.date(2026, 10, 5), from: F.now, to: F.date(2026, 10, 9, 0, 1))
        #expect(rolled.selected == F.date(2026, 10, 5))
    }

    @Test func rolloverIntoNewMonthShowsNewCurrentMonth() {
        let october = MonthGrid(containing: F.now, calendar: F.minsk)
        let lastEvening = F.date(2026, 10, 31, 23, 50)
        let midnight = F.date(2026, 11, 1, 0, 5)
        let fromToday = october.rolledOver(selected: F.date(2026, 10, 31), from: lastEvening, to: midnight)
        #expect(fromToday.month.start == F.date(2026, 11, 1))
        #expect(fromToday.selected == F.date(2026, 11, 1))
        // Выбранное 5-е не переносится в будущее 5 ноября: ближайший прошедший день — сегодня.
        let fromFifth = october.rolledOver(selected: F.date(2026, 10, 5), from: lastEvening, to: midnight)
        #expect(fromFifth.month.start == F.date(2026, 11, 1))
        #expect(fromFifth.selected == F.date(2026, 11, 1))
    }

    @Test func rolloverKeepsPastMonthInView() {
        let september = MonthGrid(containing: F.date(2026, 9, 1), calendar: F.minsk)
        let rolled = september.rolledOver(
            selected: F.date(2026, 9, 12), from: F.date(2026, 10, 31, 23, 50), to: F.date(2026, 11, 1, 0, 5)
        )
        #expect(rolled.month == september)
        #expect(rolled.selected == F.date(2026, 9, 12))
    }
}
