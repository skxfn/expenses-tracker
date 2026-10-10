import Foundation
import ExpenseCore

/// Строки статистики: ключи каталога (`stats.*`, `home.compare*`, `range.compare`, `home.empty.period.*`,
/// `a11y.money`) + данные через форматтеры Core. Даты — `RussianDateFormatter` (D7), суммы — `MoneyFormatter.Style`.
struct StatsTexts {
    let money: MoneyFormatter
    let dates: RussianDateFormatter

    init(money: MoneyFormatter, calendar: Calendar, now: Date) {
        self.money = money
        dates = RussianDateFormatter(calendar: calendar, now: now)
    }

    private var calendar: Calendar { dates.calendar }
    private var now: Date { dates.now }

    // MARK: - Сводка

    /// «Потрачено за 8 дней» и формы `stats.summary.lead.*`: сегодня, неделя, прошедший месяц, год.
    func lead(_ period: StatsPeriod, summary: StatsSummary) -> String {
        let isCurrent = period.contains(now)
        let start = period.interval.start
        switch period.kind {
        case .day where isCurrent:
            return L10n.format("stats.summary.lead.today")
        case .day:
            return L10n.format("stats.summary.lead", 1)
        case .week:
            return L10n.format("stats.summary.lead.week")
        case .month where isCurrent:
            return L10n.format("stats.summary.lead", summary.averagedDayCount)
        case .month:
            return L10n.format("stats.summary.lead.month", monthName(start))
        case .year where isCurrent:
            return L10n.format("stats.summary.lead.yearToDate")
        case .year:
            return L10n.format("stats.summary.lead.year", yearText(start))
        case nil:
            return L10n.format("stats.summary.lead", PeriodSelection.dayCount(of: period.interval, calendar: calendar))
        }
    }

    /// «на **38 ⃅ меньше**, чем в прошлом месяце» и формы (D5): больше / примерно как / трат не было.
    func comparison(_ summary: StatsSummary) -> AttributedString {
        let reference = comparisonReference(summary.comparisonReference)
        let difference = money.string(fromMinor: summary.differenceMinor, style: .difference)
        switch summary.trend {
        case .less: return L10n.attributed("home.compare", difference, reference)
        case .more: return L10n.attributed("home.compare.more", difference, reference)
        case .same: return AttributedString(L10n.format("home.compare.same", reference))
        case .noPrevious: return AttributedString(L10n.format("home.compare.noPrev", reference))
        }
    }

    /// «18 трат · в среднем 51,54 ⃅ в день».
    func meta(_ summary: StatsSummary) -> String {
        L10n.format("stats.summary.meta", summary.count, money.string(fromMinor: summary.averagePerDayMinor))
    }

    /// Пометка отфильтрованного блока: «только Продукты».
    func filterMark(_ group: CategoryVizGroup) -> String {
        L10n.format("viz.drill.filter", VizText.name(group))
    }

    // MARK: - Пустой период

    /// «В сентябре трат не было», «В октябре пока нет трат», «Сегодня пока нет трат», «6 окт трат не было»,
    /// «С 2 по 4 окт трат не было» (`home.empty.period.*`): «пока нет» — период идёт, «не было» — прошёл.
    func emptyPeriod(_ period: StatsPeriod) -> String {
        let isCurrent = period.contains(now)
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
            return L10n.format(isCurrent ? "home.empty.period.in.current" : "home.empty.period.in.past", yearText(start))
        case .week, nil:
            // Своего «пока нет» для диапазона в copy.json нет — и для идущего свой период «не было».
            return rangePast(period)
        }
    }

    // MARK: - Названия периода

    /// Период словами для VoiceOver и легенды: «октябрь», «5–11 октября», «8 октября», «2026».
    func periodName(_ period: StatsPeriod, month style: RussianDateFormatter.MonthStyle = .full) -> String {
        let start = period.interval.start
        switch period.kind {
        case .month: return monthName(start)
        case .day: return style == .full ? dates.dayMonth(start) : dates.short(start)
        case .year: return yearText(start)
        case .week, nil: return dates.range(period.interval, month: style)
        }
    }

    /// Прошлый период — подпись второй кривой «Темпа»: «сентябрь», «28 сен – 4 окт», «2025».
    func previousName(_ period: StatsPeriod, month style: RussianDateFormatter.MonthStyle = .abbreviated) -> String {
        periodName(period.previous(in: calendar), month: style)
    }

    // MARK: - Столбики

    /// Подсказка и подпись оси: «Сегодня», «Вчера», «чт, 1 окт»; час — «14:00»; месяц — «Октябрь».
    func bucketTitle(_ bucket: StatsTimeBucket, step: StatsTimeStep) -> String {
        let start = bucket.interval.start
        switch step {
        case .hour: return dates.hour(start)
        case .month: return RussianWords.capitalized(monthName(start))
        case .day, .week: return relativeDay(start) ?? dates.shortWithWeekday(start)
        }
    }

    /// `stats.days.bar.a11y`: «Сегодня, 57,20 рубля», «Четверг, 1 октября, 12 рублей».
    func bucketAccessibility(_ bucket: StatsTimeBucket, step: StatsTimeStep) -> String {
        let start = bucket.interval.start
        let title: String = switch step {
        case .hour: dates.hour(start)
        case .month: RussianWords.capitalized(monthName(start)) + yearSuffix(start)
        case .day, .week: relativeDay(start) ?? dates.full(start)
        }
        return title + ", " + spoken(bucket.totalMinor)
    }

    /// Подпись под столбиком: число дня, «пн» у недели, час, «Янв» у года.
    func axisLabel(_ bucket: StatsTimeBucket, step: StatsTimeStep, period: StatsPeriod) -> String {
        let start = bucket.interval.start
        switch step {
        case .hour:
            return String(calendar.component(.hour, from: start))
        case .month:
            return L10n.format("stats.year.months.\(calendar.component(.month, from: start))")
        case .day, .week:
            guard period.kind == .week else { return String(calendar.component(.day, from: start)) }
            return RussianWords.weekday(calendar.component(.weekday, from: start), .abbreviated)
        }
    }

    /// «в среднем 51,54» — подпись линии средней.
    func averageLabel(_ minor: Int64) -> String {
        L10n.format("stats.days.avg", money.string(fromMinor: minor, style: .plain))
    }

    /// Заголовок графика VoiceOver: «Траты по дням за октябрь», «Траты по часам за 8 октября».
    func seriesAccessibility(_ period: StatsPeriod, step: StatsTimeStep) -> String {
        switch step {
        case .hour:
            return L10n.format("stats.dayView.a11y", dates.dayMonth(period.interval.start))
        case .month:
            // TODO(copy): «Траты по месяцам за 2026» — строки для вида «Год» в copy.json нет.
            return "Траты по месяцам за " + periodName(period)
        case .day, .week:
            return L10n.format("stats.days.a11y", periodName(period))
        }
    }

    // MARK: - Темп

    /// Сумма прогноза без знака валюты: «≈ 1 600» (2 значащие цифры, `StatsForecast.roundedMinor`).
    /// Знак валюты рядом даёт `AmountText`, в подписи у конца кривой его нет (макет `04-stats`).
    func approximate(_ minor: Int64) -> String {
        "≈" + TextSpacing.nonBreaking + money.string(fromMinor: minor, style: .wholeUnits)
    }

    /// «к 31 октября при текущем темпе» / «итог за сентябрь».
    func paceNote(_ period: StatsPeriod, hasForecast: Bool) -> String {
        if hasForecast, let target = dates.paceTarget(for: period) {
            return L10n.format("stats.pace.note", target)
        }
        return L10n.format("stats.pace.note.past", periodName(period, month: .abbreviated))
    }

    /// Подпись оси «Темпа»: номер дня в периоде (с 1), текст и сегодняшний ли он.
    struct AxisDay {
        let day: Int
        let text: String
        let isCurrent: Bool
    }

    /// Подписи оси «Темпа»: месяц — «1, 8, 15, 22, 31» и сегодня; неделя — «пн … вс»; год — «Янв, Апр, Июл, Окт».
    /// `dayCount` — длина оси (прошлый период бывает длиннее), `lastIndex` — последний день текущего периода.
    func paceAxisLabels(_ period: StatsPeriod, dayCount: Int, lastIndex: Int, todayIndex: Int?) -> [AxisDay] {
        let start = period.interval.start
        switch period.kind {
        case .year:
            return [1, 4, 7, 10].compactMap { month in
                var components = calendar.dateComponents([.year], from: start)
                components.month = month
                components.day = 1
                guard let date = calendar.date(from: components),
                      let day = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
                return AxisDay(day: day, text: L10n.format("stats.year.months.\(month)"), isCurrent: false)
            }
        case .week:
            return (0...lastIndex).map { index in
                let date = calendar.date(byAdding: .day, value: index, to: start) ?? start
                let weekday = RussianWords.weekday(calendar.component(.weekday, from: date), .abbreviated)
                return AxisDay(day: index + 1, text: weekday, isCurrent: index == todayIndex)
            }
        default:
            let pinned = [todayIndex, lastIndex].compactMap { $0 }
            return StatsChartAxes.labeledIndices(count: dayCount, pinned: pinned).map { index in
                AxisDay(day: index + 1, text: String(index + 1), isCurrent: index == todayIndex)
            }
        }
    }

    /// Описание графика «Темп» для VoiceOver (`stats.pace.a11y.*`).
    func paceAccessibility(_ pace: StatsPaceState, period: StatsPeriod) -> String {
        let previousPeriod = period.previous(in: calendar)
        let currentDay = pace.comparison.current.last
        let dayNumber = currentDay.map { calendar.component(.day, from: $0.date) } ?? 0
        var parts = [L10n.format("stats.pace.a11y")]
        if let currentDay {
            parts.append(L10n.format(
                "stats.pace.a11y.current",
                RussianWords.capitalized(periodName(period)), spoken(currentDay.cumulativeMinor), dayNumber
            ))
        }
        let previous = pace.comparison.previous
        let sameIndex = pace.comparison.current.count - 1
        let sameDay = previous.indices.contains(sameIndex) ? previous[sameIndex] : previous.last
        if let sameDay, let previousTotal = previous.last {
            let name = RussianWords.capitalized(periodName(previousPeriod))
            // «… и 1 580 рублей за месяц» — строка есть только для месяца.
            parts.append(period.kind == .month
                ? L10n.format("stats.pace.a11y.previous", name, spoken(sameDay.cumulativeMinor), dayNumber, spoken(previousTotal.cumulativeMinor))
                : L10n.format("stats.pace.a11y.current", name, spoken(sameDay.cumulativeMinor), dayNumber))
        }
        if let forecast = pace.forecast {
            parts.append(L10n.format("stats.pace.a11y.forecast", periodName(period), spoken(forecast.roundedMinor)))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Привычки

    /// «Пн»
    func weekdayShort(_ weekday: Int) -> String {
        RussianWords.capitalized(RussianWords.weekday(weekday, .abbreviated))
    }

    /// «Больше всего тратится **по пятницам**».
    func peakWeekday(_ weekday: Int) -> AttributedString {
        L10n.attributed("stats.habits.insight.day", "по " + RussianWords.weekday(weekday, .dativePlural))
    }

    /// Будни против выходных.
    func weekSplit(_ split: StatsWeekSplit) -> AttributedString {
        switch split {
        case .weekdays: L10n.attributed("stats.habits.insight.weekend")
        case .weekend: L10n.attributed("stats.habits.insight.weekendMore")
        case .even: L10n.attributed("stats.habits.insight.even")
        }
    }

    /// `stats.habits.a11y`: «В среднем за день: понедельник — 72 рубля, …».
    func habitsAccessibility(_ habits: StatsHabits) -> String {
        let items = habits.averages.map { average in
            L10n.format("stats.habits.a11y.item", RussianWords.weekday(average.weekday, .nominative), spoken(average.averageMinor))
        }
        return L10n.format("stats.habits.a11y", items.joined(separator: ", "))
    }

    // MARK: - Год

    /// `stats.year.a11y`: «Траты за 2026 год по дням: … от 0 до 75 рублей и больше. Данные с 1 января по 8 октября».
    func yearAccessibility(_ year: StatsYearState) -> String {
        let days = year.months.flatMap { $0 }
        guard let first = days.first?.interval.start, let last = days.last?.interval.start else { return "" }
        let lastData = min(last, calendar.startOfDay(for: now))
        return L10n.format(
            "stats.year.a11y",
            String(year.year), spoken(year.scale.thresholds.last ?? 0), dates.dayMonth(first), dates.dayMonth(lastData)
        )
    }

    // MARK: - Общее

    /// `a11y.money`: «142,60 рубля», «5 рублей», «1 рубль».
    func spoken(_ minor: Int64) -> String {
        minor % Money.minorUnitsPerMajor == 0
            ? L10n.format("a11y.money", minor / Money.minorUnitsPerMajor)
            : L10n.format("a11y.money.fraction", money.string(fromMinor: minor, style: .plain))
    }

    // MARK: - Внутреннее

    private func comparisonReference(_ reference: StatsComparisonReference) -> String {
        switch reference {
        case .yesterday: L10n.format("home.compare.day.current")
        case .dayBefore: L10n.format("home.compare.day.past")
        case .lastWeek: L10n.format("home.compare.week.current")
        case .lastMonth: L10n.format("home.compare.month.current")
        case .lastYear: L10n.format("home.compare.year.current")
        case .month(let month): L10n.format("home.compare.month.past", RussianWords.month(month, .prepositional))
        case .year(let year): L10n.format("home.compare.year.past", String(year))
        case .range(let interval): L10n.format("range.compare", dates.range(interval))
        }
    }

    /// «С 2 по 4 окт трат не было»: месяц у начала — только если он другой.
    private func rangePast(_ period: StatsPeriod) -> String {
        let first = period.interval.start
        let last = StatisticsModel.lastDay(of: period, calendar: calendar)
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let from = sameMonth ? String(calendar.component(.day, from: first)) : dates.short(first)
        return L10n.format("home.empty.period.range.past", from, dates.short(last))
    }

    /// «Сегодня» / «Вчера» (`header.title.day.*`) или `nil`.
    private func relativeDay(_ day: Date) -> String? {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day
        switch offset {
        case 0: return L10n.format("header.title.day.today")
        case -1: return L10n.format("header.title.day.yesterday")
        default: return nil
        }
    }

    /// «октябрь»
    private func monthName(_ date: Date) -> String {
        RussianWords.month(calendar.component(.month, from: date), .nominative)
    }

    /// «2026»
    private func yearText(_ date: Date) -> String {
        String(calendar.component(.year, from: date))
    }

    /// « 2025», если год не текущий.
    private func yearSuffix(_ date: Date) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year) ? "" : TextSpacing.nonBreaking + yearText(date)
    }
}
