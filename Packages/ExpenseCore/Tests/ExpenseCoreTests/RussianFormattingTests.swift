import Foundation
import Testing
@testable import ExpenseCore

/// Русские даты, словоформы, проценты и пробелы (D5, D7, design/INTEGRATION.md §5.2).
/// В ожиданиях `_` — неразрывный пробел U+00A0.
@Suite struct RussianFormattingTests {
    private typealias F = StatsFixture
    private let dates = RussianDateFormatter(calendar: F.minsk, now: F.now)

    private func visible(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: "_")
    }

    // MARK: - Даты

    @Test func shortDates() {
        #expect(visible(dates.short(F.now)) == "8_окт")
        #expect(visible(dates.short(F.date(2026, 5, 8))) == "8_мая")
        #expect(visible(dates.short(F.date(2025, 10, 1))) == "1_окт_2025")
        #expect(visible(dates.shortWithWeekday(F.now)) == "чт, 8_окт")
        #expect(visible(dates.shortWithWeekday(F.date(2026, 10, 6), capitalized: true)) == "Вт, 6_окт")
    }

    @Test func dayMonthAndFullDates() {
        #expect(visible(dates.dayMonth(F.date(2026, 10, 31))) == "31_октября")
        #expect(visible(dates.dayMonth(F.date(2025, 12, 31))) == "31_декабря_2025")
        #expect(visible(dates.full(F.now)) == "Четверг, 8_октября")
        #expect(visible(dates.full(F.date(2026, 9, 27), shortWeekday: true)) == "Вс, 27_сентября")
        #expect(visible(dates.full(F.date(2025, 10, 8))) == "Среда, 8_октября_2025")
    }

    /// Свои таблицы совпадают с системным wide-форматом (с точностью до вида пробела).
    @Test(arguments: 1...12)
    func fullDateMatchesSystemWideFormat(month: Int) {
        let style = Date.FormatStyle(
            locale: F.ru, calendar: F.minsk, timeZone: F.minsk.timeZone, capitalizationContext: .beginningOfSentence
        ).weekday(.wide).day().month(.wide)
        for day in [1, 2, 3, 4, 5, 6, 7] {
            let date = F.date(2026, month, day, 12)
            #expect(dates.full(date).replacingOccurrences(of: "\u{00A0}", with: " ") == style.format(date))
        }
    }

    @Test func ranges() {
        func range(_ start: Date, _ end: Date, _ month: RussianDateFormatter.MonthStyle = .abbreviated) -> String {
            visible(dates.range(DateInterval(start: start, end: end), month: month))
        }
        #expect(range(F.date(2026, 10, 5), F.date(2026, 10, 8)) == "5–7_окт")
        #expect(range(F.date(2026, 9, 28), F.date(2026, 10, 5)) == "28_сен_– 4_окт")
        #expect(range(F.date(2026, 10, 5), F.date(2026, 10, 6)) == "5_окт")
        #expect(range(F.date(2025, 10, 5), F.date(2025, 10, 8)) == "5–7_окт_2025")
        #expect(range(F.date(2026, 10, 5), F.date(2026, 10, 8), .full) == "5–7_октября")
        #expect(range(F.date(2026, 9, 28), F.date(2026, 10, 5), .full) == "28_сентября_– 4_октября")
    }

    // MARK: - Сравнение и темп

    @Test func comparisonReferences() {
        let cases: [(StatsComparisonReference, String)] = [
            (.yesterday, "вчера"),
            (.dayBefore, "накануне"),
            (.lastWeek, "на прошлой неделе"),
            (.lastMonth, "в прошлом месяце"),
            (.lastYear, "в прошлом году"),
            (.month(8), "в августе"),
            (.month(5), "в мае"),
            (.year(2024), "в 2024"),
            (.range(DateInterval(start: F.date(2026, 10, 2), end: F.date(2026, 10, 5))), "за 2–4_окт"),
            (.range(DateInterval(start: F.date(2026, 9, 21), end: F.date(2026, 9, 28))), "за 21–27_сен")
        ]
        for (reference, expected) in cases {
            #expect(visible(dates.comparisonReference(reference)) == expected)
        }
    }

    @Test func paceTargets() {
        let week = StatsPeriod.current(.week, now: F.now, calendar: F.minsk)
        #expect(dates.paceTarget(for: week) == "воскресенью")
        let sundayFirst = F.makeCalendar(timeZone: "Europe/Minsk", firstWeekday: 1)
        let usWeek = StatsPeriod.current(.week, now: F.now, calendar: sundayFirst)
        #expect(RussianDateFormatter(calendar: sundayFirst, now: F.now).paceTarget(for: usWeek) == "субботе")

        #expect(visible(dates.paceTarget(for: F.october) ?? "") == "31_октября")
        let year = StatsPeriod.current(.year, now: F.now, calendar: F.minsk)
        #expect(visible(dates.paceTarget(for: year) ?? "") == "31_декабря")
        #expect(dates.hour(F.date(2026, 10, 8, 9)) == "09:00")
        #expect(dates.hour(F.date(2026, 10, 8, 14, 30)) == "14:30")
        #expect(dates.paceTarget(for: .current(.day, now: F.now, calendar: F.minsk)) == nil)
        #expect(dates.paceTarget(for: .custom(DateInterval(start: F.date(2026, 10, 1), end: F.date(2026, 10, 3)))) == nil)
    }

    // MARK: - Словоформы

    @Test func monthForms() {
        #expect((1...12).map { RussianWords.month($0, .abbreviated) }
            == ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"])
        #expect(RussianWords.month(9, .nominative) == "сентябрь")
        #expect(RussianWords.month(10, .genitive) == "октября")
        #expect(RussianWords.month(8, .prepositional) == "августе")
        #expect(RussianWords.capitalized(RussianWords.month(5, .nominative)) == "Май")
    }

    @Test func weekdayForms() {
        // Нумерация Calendar: 1 — воскресенье, 6 — пятница.
        #expect(RussianWords.weekday(6, .dativePlural) == "пятницам")
        #expect(RussianWords.weekday(1, .dativePlural) == "воскресеньям")
        #expect(RussianWords.weekday(1, .dativeSingular) == "воскресенью")
        #expect(RussianWords.weekday(4, .dativeSingular) == "среде")
        #expect(RussianWords.weekday(2, .nominative) == "понедельник")
        #expect(RussianWords.weekday(5, .abbreviated) == "чт")
    }

    // MARK: - Проценты и пробелы

    @Test(arguments: [
        (0.35, "35%"),
        (0.345, "35%"),
        (0.3449, "34%"),
        (0.01, "1%"),
        (0.0099, "<1%"),
        (0.0001, "<1%"),
        (1.0, "100%"),
        (0.0, "0%"),
        (-0.2, "0%"),
        (Double.nan, "0%")
    ])
    func percents(share: Double, expected: String) {
        #expect(PercentFormatter.string(fromShare: share) == expected)
    }

    @Test func spacesNormalizeToNoBreakSpace() {
        #expect(TextSpacing.normalized("1\u{202F}000\u{2009}2\u{2007}3 4\u{00A0}5") == "1\u{00A0}000\u{00A0}2\u{00A0}3 4\u{00A0}5")
        #expect(TextSpacing.normalized("Ещё одна") == "Ещё одна")
    }
}
