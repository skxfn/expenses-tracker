import Foundation
import ExpenseCore

/// Строки календаря: ключи каталога (`cal.*`, `header.*`, `a11y.money`) + данные через форматтеры Core.
/// Суммы для VoiceOver — словом «рубль» (`a11y.money`), даты — `RussianDateFormatter` (D7).
struct CalendarStrings {
    let money: MoneyFormatter
    let dates: RussianDateFormatter
    private let calendar: Calendar

    init(money: MoneyFormatter, calendar: Calendar, now: Date) {
        self.money = money
        self.calendar = calendar
        dates = RussianDateFormatter(calendar: calendar, now: now)
    }

    // MARK: Шапка

    /// «Октябрь» и «2026» (`cal.header.month`: год в календаре всегда).
    func monthTitle(_ month: MonthGrid) -> (name: String, year: String) {
        let parts = calendar.dateComponents([.month, .year], from: month.start)
        return (RussianWords.capitalized(RussianWords.month(parts.month ?? 1, .nominative)), String(parts.year ?? 0))
    }

    /// `cal.header.a11y`: «Месяц: октябрь 2026».
    func headerAccessibility(_ month: MonthGrid) -> String {
        L10n.format("cal.header.a11y", monthAndYear(month))
    }

    /// `cal.grid.a11y`: «Траты по дням, октябрь 2026».
    func gridAccessibility(_ month: MonthGrid) -> String {
        L10n.format("cal.grid.a11y", monthAndYear(month))
    }

    /// `header.prev.a11y` / `header.next.a11y`: «Предыдущий месяц, сентябрь»; год — если другой.
    func stepAccessibility(from month: MonthGrid, to target: MonthGrid, key: String) -> String {
        let targetYear = calendar.component(.year, from: target.start)
        let name = calendar.component(.year, from: month.start) == targetYear
            ? monthName(target)
            : monthAndYear(target)
        return L10n.format(key, name)
    }

    /// `cal.summary`: «**412,30 Br** за 8 дней · больше всего 2 окт»; пустой месяц — `cal.summary.empty`.
    func summary(_ summary: CalendarModel.Summary, month: MonthGrid, isCurrent: Bool) -> AttributedString {
        guard let peak = summary.peakDay, summary.totalMinor > 0 else {
            let monthIn = RussianWords.month(calendar.component(.month, from: month.start), .prepositional)
            let key = isCurrent ? "home.empty.period.in.current" : "home.empty.period.in.past"
            return AttributedString(L10n.format(key, monthIn))
        }
        return L10n.attributed(
            "cal.summary",
            money.string(fromMinor: summary.totalMinor, style: .phrase),
            summary.dayCount,
            dates.short(peak)
        )
    }

    // MARK: Клетка дня

    /// Число в клетке.
    func dayNumber(_ date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    /// Сумма в клетке (`cal.cell.amount`): «64,10» · «1 234» · «12 тыс»; без трат — `nil`.
    func cellAmount(_ minor: Int64) -> String? {
        minor > 0 ? money.string(fromMinor: minor, style: .calendarCell) : nil
    }

    /// `cal.day.a11y` и его формы: «Четверг, 1 октября, 64,10 рубля»; без трат — «…, трат нет»;
    /// сегодня выбранный — `cal.day.today.a11y` (в нём уже «выбран»); день-максимум — `cal.day.max.a11y`.
    func dayAccessibility(_ day: CalendarModel.Day, isSelected: Bool, isPeak: Bool) -> String {
        let label: String
        if day.isToday {
            let date = lowercasedWeekday(day.date) + ", " + dates.dayMonth(day.date)
            if isSelected, day.totalMinor > 0 {
                label = L10n.format("cal.day.today.a11y", date, spoken(day.totalMinor))
            } else {
                label = withAmount(String(localized: "header.title.day.today") + ", " + date, day)
            }
        } else if day.isFuture {
            label = dates.full(day.date)
        } else {
            label = withAmount(dates.full(day.date), day)
        }
        return isPeak ? L10n.format("cal.day.max.a11y", label) : label
    }

    /// Озвучивает ли подпись выбор сама (`cal.day.today.a11y`) — тогда трейт `.isSelected` не нужен.
    func accessibilityStatesSelection(_ day: CalendarModel.Day, isSelected: Bool) -> Bool {
        day.isToday && isSelected && day.totalMinor > 0
    }

    // MARK: Шкала

    /// `cal.legend.title`: «Br за день».
    var legendTitle: String {
        L10n.format("cal.legend.title", money.currencySymbol)
    }

    /// `cal.legend.items`: «0 · до 25 · 25+ · 50+ · 75+»; при трёхзначных порогах — «<125».
    func legendItems(_ scale: StatsHeatScale) -> [String] {
        let bounds = scale.thresholds.map { money.string(fromMinor: $0, style: .wholeUnits) }
        guard let first = bounds.first, let firstMinor = scale.thresholds.first else { return ["0"] }
        let belowKey = firstMinor >= Self.shortLegendFromMinor ? "cal.legend.items.belowShort" : "cal.legend.items.below"
        return ["0", L10n.format(belowKey, first)] + bounds.map { L10n.format("cal.legend.items.from", $0) }
    }

    /// `cal.legend.a11y`: «Шкала: 0, меньше 25, от 25, от 50, от 75 рублей за день»; последний порог —
    /// со словом валюты (`cal.legend.a11y.last`), без порогов — «Шкала: 0 рублей за день».
    func legendAccessibility(_ scale: StatsHeatScale) -> String {
        let bounds = scale.thresholds.map { money.string(fromMinor: $0, style: .wholeUnits) }
        guard let first = bounds.first, let last = bounds.last else { return L10n.format("cal.legend.a11y", spoken(0)) }
        let items = ["0", L10n.format("cal.legend.a11y.below", first)]
            + bounds.dropLast().map { L10n.format("cal.legend.a11y.from", $0) }
            + [L10n.format("cal.legend.a11y.last", last)]
        return L10n.format("cal.legend.a11y", items.joined(separator: ", "))
    }

    // MARK: Лист дня

    /// `cal.day.title`: «Четверг, 8 октября»; запасной — «Чт, 8 октября».
    func dayTitle(_ date: Date, shortWeekday: Bool = false) -> String {
        dates.full(date, shortWeekday: shortWeekday)
    }

    /// `cal.day.sheet.a11y`: «Траты за 8 октября».
    func sheetAccessibility(_ date: Date) -> String {
        L10n.format("cal.day.sheet.a11y", dates.dayMonth(date))
    }

    /// `cal.addForDay`: «Записать на 8 окт».
    func addForDay(_ date: Date) -> String {
        L10n.format("cal.addForDay", dates.short(date))
    }

    /// `cal.addForDay.a11y`: «Записать трату на 8 октября».
    func addForDayAccessibility(_ date: Date) -> String {
        L10n.format("cal.addForDay.a11y", dates.dayMonth(date))
    }

    /// `a11y.money`: «142,60 рубля», «5 рублей», «1 рубль».
    func spoken(_ minor: Int64) -> String {
        minor % Money.minorUnitsPerMajor == 0
            ? L10n.format("a11y.money", minor / Money.minorUnitsPerMajor)
            : L10n.format("a11y.money.fraction", money.string(fromMinor: minor, style: .plain))
    }

    // MARK: Внутреннее

    /// Порог, с которого «до 125» не помещается в капсулу 44 (copy.json → `cal.legend.items`, risk).
    private static let shortLegendFromMinor: Int64 = 100 * Money.minorUnitsPerMajor

    /// «октябрь 2026»
    private func monthAndYear(_ month: MonthGrid) -> String {
        monthName(month) + " " + String(calendar.component(.year, from: month.start))
    }

    /// «октябрь»
    private func monthName(_ month: MonthGrid) -> String {
        RussianWords.month(calendar.component(.month, from: month.start), .nominative)
    }

    /// «четверг»
    private func lowercasedWeekday(_ date: Date) -> String {
        RussianWords.weekday(calendar.component(.weekday, from: date), .nominative)
    }

    /// «…, 64,10 рубля» или «…, трат нет» (`cal.day.a11y.empty`).
    private func withAmount(_ date: String, _ day: CalendarModel.Day) -> String {
        day.totalMinor > 0 ? date + ", " + spoken(day.totalMinor) : L10n.format("cal.day.a11y.empty", date)
    }
}
