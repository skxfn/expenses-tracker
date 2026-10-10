import Foundation
import ExpenseCore

/// Тексты итога периода, общие для главной и статистики: фраза-сравнение (`home.compare*`, `range.compare`),
/// пустой период (`home.empty.period.*`) и сумма для VoiceOver (`a11y.money`).
/// Суммы — `MoneyFormatter.Style`, даты — `RussianDateFormatter` (D7).
struct SummaryTexts {
    let money: MoneyFormatter
    let dates: RussianDateFormatter

    private var calendar: Calendar { dates.calendar }

    // MARK: - Сравнение (§4.7, D5)

    /// «на **38 ⃅ меньше**, чем в прошлом месяце» и формы: больше / примерно как / трат не было.
    /// Выделенная часть — `stronglyEmphasized`: стиль (SF 600 графитом) задаёт вид.
    func comparison(_ summary: StatsSummary, period: StatsPeriod) -> AttributedString {
        let reference = reference(summary.comparisonReference, period: period)
        let difference = money.string(fromMinor: summary.differenceMinor, style: .difference)
        switch summary.trend {
        case .less: return L10n.attributed("home.compare", difference, reference)
        case .more: return L10n.attributed("home.compare.more", difference, reference)
        case .same: return AttributedString(L10n.format("home.compare.same", reference))
        case .noPrevious: return AttributedString(L10n.format("home.compare.noPrev", reference))
        }
    }

    // MARK: - Пустой период

    /// «В октябре пока нет трат» (период идёт) / «В сентябре трат не было» (прошёл), «Сегодня пока нет трат»,
    /// «6 окт трат не было», «С 2 по 4 окт трат не было» (`home.empty.period.*`).
    func emptyPeriod(_ period: StatsPeriod) -> String {
        let isCurrent = period.contains(dates.now)
        let start = period.interval.start
        switch period.kind {
        case .day:
            return isCurrent
                ? L10n.format("home.empty.period.day.current")
                : L10n.format("home.empty.period.day.past", dates.short(start))
        case .week where isCurrent:
            return L10n.format("home.empty.period.week.current")
        case .month:
            let month = RussianWords.month(calendar.component(.month, from: start), .prepositional)
            return L10n.format(isCurrent ? "home.empty.period.in.current" : "home.empty.period.in.past", month)
        case .year:
            let year = String(calendar.component(.year, from: start))
            return L10n.format(isCurrent ? "home.empty.period.in.current" : "home.empty.period.in.past", year)
        case .week, nil:
            // Своего «пока нет» для диапазона в copy.json нет — и для идущего свой период «не было».
            return rangePast(period.interval)
        }
    }

    // MARK: - VoiceOver

    /// `a11y.money`: «142,60 рубля», «5 рублей», «1 рубль».
    func spoken(_ minor: Int64) -> String {
        minor % Money.minorUnitsPerMajor == 0
            ? L10n.format("a11y.money", minor / Money.minorUnitsPerMajor)
            : L10n.format("a11y.money.fraction", money.string(fromMinor: minor, style: .plain))
    }

    // MARK: - Внутреннее

    /// С чем сравнили: «в прошлом месяце», «в августе», «накануне», «за 2–4 окт».
    private func reference(_ reference: StatsComparisonReference, period: StatsPeriod) -> String {
        switch reference {
        case .yesterday: L10n.format("home.compare.day.current")
        case .dayBefore: L10n.format("home.compare.day.past")
        case .lastWeek: L10n.format("home.compare.week.current")
        case .lastMonth: L10n.format("home.compare.month.current")
        case .lastYear: L10n.format("home.compare.year.current")
        case .month(let month): L10n.format("home.compare.month.past", RussianWords.month(month, .prepositional))
        case .year(let year): L10n.format("home.compare.year.past", String(year))
        case .range(let interval):
            L10n.format(period.kind == nil ? "range.compare" : "home.compare.week.past", dates.range(interval))
        }
    }

    /// «С 2 по 4 окт трат не было», «С 28 сен по 4 окт трат не было»: месяц у начала — только если он другой;
    /// один день — «6 окт трат не было».
    private func rangePast(_ interval: DateInterval) -> String {
        let first = interval.start
        let last = lastDay(of: interval)
        guard !calendar.isDate(first, inSameDayAs: last) else {
            return L10n.format("home.empty.period.day.past", dates.short(first))
        }
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let from = sameMonth ? String(calendar.component(.day, from: first)) : dates.short(first)
        return L10n.format("home.empty.period.range.past", from, dates.short(last))
    }

    /// Начало последнего дня полуоткрытого интервала.
    private func lastDay(of interval: DateInterval) -> Date {
        let endDay = calendar.startOfDay(for: interval.end)
        guard endDay == interval.end else { return endDay }
        return calendar.date(byAdding: .day, value: -1, to: endDay) ?? endDay
    }
}
