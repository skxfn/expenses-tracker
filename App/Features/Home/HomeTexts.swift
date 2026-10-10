import Foundation
import ExpenseCore

/// Тексты главной: фраза-сравнение (`home.compare*`, `range.compare`), пустой период (`home.empty.period.*`),
/// заголовки дней (`feed.dayHeader.*`) и подписи VoiceOver. Ключи — из каталога, данные — форматтеры Core:
/// суммы — `MoneyFormatter.Style`, даты — `RussianDateFormatter` (D7), озвучка сумм — `a11y.money`.
struct HomeTexts {
    let money: MoneyFormatter
    let dates: RussianDateFormatter

    init(money: MoneyFormatter, calendar: Calendar, now: Date) {
        self.money = money
        dates = RussianDateFormatter(calendar: calendar, now: now)
    }

    private var calendar: Calendar { dates.calendar }

    // MARK: - Сравнение (§4.7, D5)

    /// «на **38 Br меньше**, чем в прошлом месяце», «примерно как …», «… трат не было».
    /// Выделенная часть — `stronglyEmphasized`: стиль (SF 600 графитом) задаёт вид.
    func comparison(_ summary: StatsSummary, period: StatsPeriod) -> AttributedString {
        let reference = reference(summary.comparisonReference, period: period)
        let difference = money.string(fromMinor: summary.differenceMinor, style: .difference)
        switch summary.trend {
        case .more: return L10n.attributed("home.compare.more", difference, reference)
        case .less: return L10n.attributed("home.compare", difference, reference)
        case .same: return AttributedString(L10n.format("home.compare.same", reference))
        case .noPrevious: return AttributedString(L10n.format("home.compare.noPrev", reference))
        }
    }

    /// С чем сравнили: «в прошлом месяце», «в августе», «накануне», «за 2–4 окт».
    private func reference(_ reference: StatsComparisonReference, period: StatsPeriod) -> String {
        switch reference {
        case .yesterday: String(localized: "home.compare.day.current")
        case .dayBefore: String(localized: "home.compare.day.past")
        case .lastWeek: String(localized: "home.compare.week.current")
        case .lastMonth: String(localized: "home.compare.month.current")
        case .lastYear: String(localized: "home.compare.year.current")
        case .month(let month): L10n.format("home.compare.month.past", RussianWords.month(month, .prepositional))
        case .year(let year): L10n.format("home.compare.year.past", String(year))
        case .range(let interval):
            L10n.format(period.kind == nil ? "range.compare" : "home.compare.week.past", dates.range(interval))
        }
    }

    // MARK: - Пустой период

    /// «В октябре пока нет трат» (период идёт) / «В сентябре трат не было» (прошёл); формы — `home.empty.period.*`.
    func emptyPeriod(_ period: StatsPeriod, isCurrent: Bool) -> String {
        let start = period.interval.start
        switch period.kind {
        case .day:
            return isCurrent
                ? String(localized: "home.empty.period.day.current")
                : L10n.format("home.empty.period.day.past", dates.short(start))
        case .month:
            let month = RussianWords.month(calendar.component(.month, from: start), .prepositional)
            return L10n.format(isCurrent ? "home.empty.period.in.current" : "home.empty.period.in.past", month)
        case .year:
            let year = String(calendar.component(.year, from: start))
            return L10n.format(isCurrent ? "home.empty.period.in.current" : "home.empty.period.in.past", year)
        case .week where isCurrent:
            return String(localized: "home.empty.period.week.current")
        case .week, nil:
            // Своего периода «пока нет» в copy.json нет: и идущий диапазон — «С … по … трат не было».
            return rangePast(period.interval)
        }
    }

    /// «С 2 по 4 окт трат не было», «С 28 сен по 4 окт трат не было»; один день — «6 окт трат не было».
    private func rangePast(_ interval: DateInterval) -> String {
        let first = interval.start
        let last = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: interval.end)) ?? first
        guard !calendar.isDate(first, inSameDayAs: last) else {
            return L10n.format("home.empty.period.day.past", dates.short(first))
        }
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let from = sameMonth ? String(calendar.component(.day, from: first)) : dates.short(first)
        return L10n.format("home.empty.period.range.past", from, dates.short(last))
    }

    // MARK: - Лента

    /// «**Сегодня** · чт, 8 окт», «**Вчера** · ср, 7 окт», «**Вт, 6 окт**»: графитом — выделенное, дата — secondary.
    func dayTitle(_ day: Date) -> AttributedString {
        let date = dates.shortWithWeekday(day)
        switch dayOffset(day) {
        case 0: return L10n.attributed("feed.dayHeader.today", date)
        case -1: return L10n.attributed("feed.dayHeader.yesterday", date)
        default:
            var title = AttributedString(dates.shortWithWeekday(day, capitalized: true))
            title.inlinePresentationIntent = .stronglyEmphasized
            return title
        }
    }

    /// `feed.dayHeader.a11y`: «Сегодня, четверг, 8 октября, 57,20 рубля», «Вторник, 6 октября, 30,50 рубля».
    func dayAccessibility(_ day: Date, totalMinor: Int64) -> String {
        let weekday = RussianWords.weekday(calendar.component(.weekday, from: day), .nominative)
        let date: String = switch dayOffset(day) {
        case 0: [String(localized: "header.title.day.today"), weekday, dates.dayMonth(day)].joined(separator: ", ")
        case -1: [String(localized: "header.title.day.yesterday"), weekday, dates.dayMonth(day)].joined(separator: ", ")
        default: dates.full(day)
        }
        return date + ", " + spoken(totalMinor)
    }

    // MARK: - VoiceOver

    /// Период для подписей «Итог и траты за …», «Траты за … по категориям»:
    /// «октябрь», «2026», «8 октября», «5–7 октября».
    func periodName(_ period: StatsPeriod) -> String {
        let start = period.interval.start
        switch period.kind {
        case .month:
            let month = RussianWords.month(calendar.component(.month, from: start), .nominative)
            let year = calendar.component(.year, from: start)
            return year == calendar.component(.year, from: dates.now)
                ? month
                : month + TextSpacing.nonBreaking + String(year)
        case .year:
            return String(calendar.component(.year, from: start))
        case .day:
            return dates.dayMonth(start)
        case .week, nil:
            return dates.range(period.interval, month: .full)
        }
    }

    /// Сумма словом «рубль» (`a11y.money`): «412,30 рубля».
    func spoken(_ minor: Int64) -> String {
        VizText(money: money).spoken(minor)
    }

    // MARK: - Внутреннее

    /// 0 — сегодня, −1 — вчера.
    private func dayOffset(_ day: Date) -> Int {
        let today = calendar.startOfDay(for: dates.now)
        return calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day)).day ?? .min
    }
}
