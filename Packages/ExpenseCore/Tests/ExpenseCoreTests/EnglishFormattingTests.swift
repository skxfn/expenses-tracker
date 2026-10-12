import Foundation
import Testing
@testable import ExpenseCore

/// Английские даты, периоды и суммы по E7/E8 (design/copy.en.json, INTEGRATION §5.5): свой en-US,
/// не формат региона. В ожиданиях `_` — неразрывный пробел U+00A0, `~` перед частью заголовка — вторичная.
@Suite struct EnglishFormattingTests {
    private typealias F = StatsFixture
    private let dates = EnglishDateFormatter(calendar: F.minsk, now: F.now)

    private func visible(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: "_")
    }

    private func parts(_ period: StatsPeriod, now: Date = F.now) -> [String] {
        EnglishDateFormatter(calendar: F.minsk, now: now).title(for: period).parts
            .map { ($0.isSecondary ? "~" : "") + visible($0.text) }
    }

    // MARK: - Даты

    @Test func shortDates() {
        #expect(visible(dates.short(F.now)) == "Oct_8")
        #expect(visible(dates.short(F.date(2026, 5, 8))) == "May_8")
        #expect(visible(dates.short(F.date(2025, 10, 1))) == "Oct_1, 2025")
        #expect(visible(dates.shortWithWeekday(F.now)) == "Thu, Oct_8")
        #expect(visible(dates.shortWithWeekday(F.date(2026, 10, 6), capitalized: true)) == "Tue, Oct_6")
    }

    @Test func dayMonthAndFullDates() {
        #expect(visible(dates.dayMonth(F.date(2026, 10, 31))) == "October_31")
        #expect(visible(dates.dayMonth(F.date(2025, 12, 31))) == "December_31, 2025")
        #expect(visible(dates.full(F.now)) == "Thursday, October_8")
        #expect(visible(dates.full(F.date(2026, 9, 30))) == "Wednesday, September_30")
        #expect(visible(dates.full(F.date(2026, 9, 27), shortWeekday: true)) == "Sun, September_27")
    }

    /// Свои таблицы совпадают с системным en-US wide-форматом (с точностью до вида пробела).
    @Test(arguments: 1...12)
    func fullDateMatchesSystemFormat(month: Int) {
        let style = Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: F.minsk, timeZone: F.minsk.timeZone)
            .weekday(.wide).month(.wide).day()
        let short = Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: F.minsk, timeZone: F.minsk.timeZone)
            .month(.abbreviated).day()
        for day in [1, 2, 3, 4, 5, 6, 7] {
            let date = F.date(2026, month, day, 12)
            #expect(dates.full(date).replacingOccurrences(of: "\u{00A0}", with: " ") == style.format(date))
            #expect(dates.short(date).replacingOccurrences(of: "\u{00A0}", with: " ") == short.format(date))
        }
    }

    @Test func ranges() {
        func range(_ start: Date, _ end: Date, _ month: DateMonthStyle = .abbreviated) -> String {
            visible(dates.range(DateInterval(start: start, end: end), month: month))
        }
        #expect(range(F.date(2026, 10, 5), F.date(2026, 10, 8)) == "Oct_5–7")
        #expect(range(F.date(2026, 9, 28), F.date(2026, 10, 5)) == "Sep_28_–_Oct_4")
        #expect(range(F.date(2026, 10, 5), F.date(2026, 10, 6)) == "Oct_5")
        #expect(range(F.date(2025, 10, 5), F.date(2025, 10, 8)) == "Oct_5–7, 2025")
        #expect(range(F.date(2026, 10, 5), F.date(2026, 10, 8), .full) == "October_5–7")
        #expect(range(F.date(2026, 9, 28), F.date(2026, 10, 5), .full) == "September_28_–_October_4")
        #expect(range(F.date(2025, 12, 28), F.date(2026, 1, 4)) == "Dec_28_–_Jan_3")
    }

    @Test func rangeBoundsSplitAtDash() {
        func bounds(_ start: Date, _ end: Date) -> [String] {
            let result = dates.rangeBounds(DateInterval(start: start, end: end))
            return [visible(result.start), visible(result.end)]
        }
        #expect(bounds(F.date(2026, 10, 2), F.date(2026, 10, 5)) == ["Oct_2", "4"])
        #expect(bounds(F.date(2026, 9, 28), F.date(2026, 10, 5)) == ["Sep_28_", "_Oct_4"])
        let russian = RussianDateFormatter(calendar: F.minsk, now: F.now)
        let ruSame = russian.rangeBounds(DateInterval(start: F.date(2026, 10, 2), end: F.date(2026, 10, 5)))
        #expect([visible(ruSame.start), visible(ruSame.end)] == ["2", "4_окт"])
        let ruCross = russian.rangeBounds(DateInterval(start: F.date(2026, 9, 28), end: F.date(2026, 10, 5)))
        #expect([visible(ruCross.start), visible(ruCross.end)] == ["28_сен", "4_окт"])
    }

    // MARK: - Заголовок периода

    @Test func titlesPutMonthFirst() {
        let week = StatsPeriod.current(.week, now: F.now, calendar: F.minsk)
        #expect(parts(week) == ["~Oct", "_5–11"])
        #expect(parts(week.previous(in: F.minsk)) == ["~Sep", "_28_–_", "~Oct", "_4"])
        let custom = StatsPeriod.custom(DateInterval(start: F.date(2026, 10, 5), end: F.date(2026, 10, 8)))
        #expect(parts(custom) == ["~Oct", "_5–7"])
        let day = StatsPeriod.current(.day, now: F.date(2026, 10, 6, 18), calendar: F.minsk)
        #expect(parts(day) == ["~Oct", "_6"])
        let lastYearDay = StatsPeriod.current(.day, now: F.date(2025, 10, 6), calendar: F.minsk)
        #expect(parts(lastYearDay) == ["~Oct", "_6", "~, 2025"])

        // Неделя через Новый год: из 2027 годов нет, из 2026 — у обоих концов.
        let newYearWeek = StatsPeriod.current(.week, now: F.date(2027, 1, 1), calendar: F.minsk)
        #expect(parts(newYearWeek, now: F.date(2027, 1, 2)) == ["~Dec", "_28", "_–_", "~Jan", "_3"])
        #expect(parts(newYearWeek) == ["~Dec", "_28", "~, 2026", "_–_", "~Jan", "_3", "~, 2027"])

        #expect(parts(F.october) == ["October"])
        let lastSeptember = StatsPeriod.current(.month, now: F.date(2025, 9, 10), calendar: F.minsk)
        #expect(parts(lastSeptember) == ["September", "~_2025"])
        #expect(parts(.current(.year, now: F.now, calendar: F.minsk)) == ["2026"])
    }

    // MARK: - Темп и слова

    @Test func paceTargetsAndOrdinals() {
        let week = StatsPeriod.current(.week, now: F.now, calendar: F.minsk)
        #expect(dates.paceTarget(for: week) == "Sunday")
        #expect(visible(dates.paceTarget(for: F.october) ?? "") == "October_31")
        let year = StatsPeriod.current(.year, now: F.now, calendar: F.minsk)
        #expect(visible(dates.paceTarget(for: year) ?? "") == "December_31")
        #expect(dates.paceTarget(for: .current(.day, now: F.now, calendar: F.minsk)) == nil)
        #expect([1, 2, 3, 4, 8, 11, 12, 13, 21, 22, 23, 31].map(dates.dayOrdinal)
            == ["1st", "2nd", "3rd", "4th", "8th", "11th", "12th", "13th", "21st", "22nd", "23rd", "31st"])
        #expect(RussianDateFormatter(calendar: F.minsk, now: F.now).dayOrdinal(8) == "8")
    }

    /// Время — 24-часовое `HH:mm` и в английской версии («14:00», не «2:00 PM»); ось «По часам» — только час.
    @Test func hoursAre24HourInBothLanguages() {
        let russian = RussianDateFormatter(calendar: F.minsk, now: F.now)
        let times = [F.date(2026, 10, 8, 0), F.date(2026, 10, 8, 9), F.date(2026, 10, 8, 14), F.date(2026, 10, 8, 23, 5)]
        #expect(times.map(dates.hour) == ["00:00", "09:00", "14:00", "23:05"])
        #expect(times.map(russian.hour) == times.map(dates.hour))
        #expect(times.map(dates.hourOfDay) == ["0", "9", "14", "23"])
        #expect(times.map(russian.hourOfDay) == times.map(dates.hourOfDay))
    }

    @Test func words() {
        #expect((1...12).map(dates.monthShort)
            == ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
        #expect(dates.monthName(9) == "September")
        #expect(dates.monthTitle(9) == "September")
        #expect(dates.monthInPhrase(8) == "August")
        // Нумерация Calendar: 1 — воскресенье, 6 — пятница.
        #expect(dates.weekdayName(6) == "Friday")
        #expect(dates.weekdayShort(2) == "Mon")
        #expect(dates.weekdayHabit(6) == "on Fridays")
        #expect(dates.inSentence("September 2025") == "September 2025")

        let russian = RussianDateFormatter(calendar: F.minsk, now: F.now)
        #expect(russian.monthTitle(9) == "Сентябрь")
        #expect(russian.monthInPhrase(8) == "августе")
        #expect(russian.weekdayHabit(6) == "по пятницам")
        #expect(russian.inSentence("Сентябрь 2025") == "сентябрь 2025")
    }

    // MARK: - Деньги

    @Test func englishMoneyKeepsSignAfterNumber() {
        let byn = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "en_US"))
        #expect(visible(byn.string(fromMinor: 141_260)) == "1,412.60_\u{20C5}")
        #expect(visible(byn.string(fromMinor: 3_800)) == "38_\u{20C5}")
        #expect(byn.string(fromMinor: 3_800, style: .plain) == "38.00")
        #expect(visible(byn.string(fromMinor: 160_000, style: .approximate)) == "≈_1,600_\u{20C5}")
        #expect(visible(byn.string(fromMinor: 103_850, style: .difference)) == "1,039_\u{20C5}")
        #expect(byn.string(fromMinor: 6_410, style: .calendarCell) == "64.10")
        #expect(byn.string(fromMinor: 123_400, style: .calendarCell) == "1,234")
        #expect(byn.string(fromMinor: 1_200_000, style: .calendarCell) == "12K")
        #expect(byn.string(fromMinor: 100_000, style: .wholeUnits) == "1,000")
        #expect(byn.decimalSeparator == ".")

        let code = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "en_US"), symbolStyle: .code)
        #expect(visible(code.string(fromMinor: 41_230)) == "412.30_BYN")
        let usd = MoneyFormatter(currencyCode: "USD", locale: Locale(identifier: "en_US"))
        #expect(usd.string(fromMinor: 41_230) == "$412.30")
        #expect(MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "ru_RU")).decimalSeparator == ",")
    }

    @Test func amountInputUsesFormatterSeparator() {
        #expect(AmountInput.sanitize("12,5", separator: ".").text == "12.5")
        #expect(AmountInput.sanitize("12.5").text == "12,5")
        #expect(AmountInput.sanitize(".", separator: ".").text == "0.")

        let byn = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "en_US"))
        var draft = ExpenseDraft(amountText: "12.5")
        let added = draft.addQuickAmount(5, formatter: byn)
        #expect(added)
        #expect(draft.amountText == "17.50")
        #expect(draft.amountMinor == 1_750)
    }
}
