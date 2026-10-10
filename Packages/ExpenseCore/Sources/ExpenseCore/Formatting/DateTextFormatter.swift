import Foundation

/// Месяц в датах и диапазонах.
public enum DateMonthStyle: Sendable {
    /// «5–7 окт», «Oct 5–7» — на экране.
    case abbreviated
    /// «5–7 октября», «October 5–7» — для VoiceOver.
    case full
}

/// Даты, периоды и названия месяцев и дней недели на языке интерфейса: русский (D7) — `RussianDateFormatter`,
/// английский (E8, en-US) — `EnglishDateFormatter`. Оба — свои таблицы, не формат региона устройства:
/// год — только если он не текущий (год `now`), неразрывный пробел внутри даты. Фразы вокруг дат — в каталоге
/// строк App; здесь — только то, что в них подставляется (`%@`), в той форме, которую ждёт строка своего языка.
public protocol DateTextFormatter: Sendable {
    /// Часовой пояс и первый день недели.
    var calendar: Calendar { get }
    /// «Сегодня»: от него считаются текущий год и относительные дни.
    var now: Date { get }

    // MARK: Даты

    /// «8 окт» / «Oct 8»; не текущий год — «8 окт 2025» / «Oct 8, 2025».
    func short(_ date: Date) -> String
    /// «чт, 8 окт» (в начале строки — «Чт, 8 окт») / «Thu, Oct 8».
    func shortWithWeekday(_ date: Date, capitalized: Bool) -> String
    /// «8 октября» / «October 8».
    func dayMonth(_ date: Date) -> String
    /// «Четверг, 8 октября» / «Thursday, October 8»; запасной при переполнении — «Чт, 8 октября» / «Thu, October 8».
    func full(_ date: Date, shortWeekday: Bool) -> String
    /// Дни полуоткрытого интервала, последний — включительно: «5–7 окт», «28 сен – 4 окт» / «Oct 5–7», «Sep 28 – Oct 4».
    func range(_ interval: DateInterval, month: DateMonthStyle) -> String
    /// Начало и конец интервала (дней ≥ 2) для фразы о пустом диапазоне `home.empty.period.range.past`:
    /// «С %1$@ по %2$@ трат не было» — «2» и «4 окт»; «No expenses %1$@–%2$@» — «Oct 2» и «4».
    func rangeBounds(_ interval: DateInterval) -> (start: String, end: String)
    /// Заголовок шапки периода: основные и вторичные части («5–7» + «окт» / «Oct» + «5–7»).
    func title(for period: StatsPeriod) -> PeriodTitle
    /// К чему прогноз «Темпа» (`stats.pace.note`): «воскресенью», «31 октября» / «Sunday», «October 31».
    /// `nil` — у «Дня» и своего периода темпа нет.
    func paceTarget(for period: StatsPeriod) -> String?
    /// Начало часа: «9:00», «14:00».
    func hour(_ date: Date) -> String
    /// Число месяца в «к 8 числу» / «as of the 8th» (`stats.pace.a11y.*`).
    func dayOrdinal(_ day: Int) -> String

    // MARK: Слова

    /// Месяц в середине фразы: «октябрь» / «October» — «Потрачено за %@», VoiceOver.
    func monthName(_ month: Int) -> String
    /// Месяц заголовком: «Октябрь» / «October».
    func monthTitle(_ month: Int) -> String
    /// Месяц после «в» / «in»: «августе» / «August» (`home.compare.month.past`, `home.empty.period.in.*`).
    func monthInPhrase(_ month: Int) -> String
    /// Сокращение месяца: «окт» / «Oct».
    func monthShort(_ month: Int) -> String
    /// День недели в середине фразы: «четверг» / «Thursday».
    func weekdayName(_ weekday: Int) -> String
    /// Сокращение дня недели: «чт» / «Thu».
    func weekdayShort(_ weekday: Int) -> String
    /// Выделенная часть вывода «Привычек» (`stats.habits.insight.day`): «по пятницам» / «on Fridays».
    func weekdayHabit(_ weekday: Int) -> String
    /// Заголовок внутри фразы: по-русски строчными («Сентябрь 2025» → «сентябрь 2025»), по-английски как есть.
    func inSentence(_ title: String) -> String
}

public extension DateTextFormatter {
    /// «чт, 8 окт» / «Thu, Oct 8».
    func shortWithWeekday(_ date: Date) -> String {
        shortWithWeekday(date, capitalized: false)
    }

    /// «Четверг, 8 октября» / «Thursday, October 8».
    func full(_ date: Date) -> String {
        full(date, shortWeekday: false)
    }

    /// «5–7 окт» / «Oct 5–7».
    func range(_ interval: DateInterval) -> String {
        range(interval, month: .abbreviated)
    }

    /// Первая буква заглавная — начало строки: «Октябрь», «Чт, 8 окт».
    func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
