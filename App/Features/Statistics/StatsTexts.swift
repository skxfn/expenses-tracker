import Foundation
import ExpenseCore

/// Строки статистики: ключи каталога (`stats.*`) + данные через форматтеры Core; сравнение, пустой период
/// и озвучка сумм — общие с главной (`shared`). Даты и слова — `DateTextFormatter` языка интерфейса (D7 / E8),
/// суммы — `MoneyFormatter.Style`.
struct StatsTexts {
    let money: MoneyFormatter
    let dates: any DateTextFormatter
    let shared: SummaryTexts

    init(money: MoneyFormatter, calendar: Calendar, now: Date) {
        self.money = money
        dates = AppLanguage.current.dateFormatter(calendar: calendar, now: now)
        shared = SummaryTexts(money: money, dates: dates)
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

    /// «18 трат · в среднем 51,54 ⃅ в день».
    func meta(_ summary: StatsSummary) -> String {
        L10n.format("stats.summary.meta", summary.count, money.string(fromMinor: summary.averagePerDayMinor))
    }

    /// То же для VoiceOver: «18 трат · в среднем 51,54 рубля в день».
    func spokenMeta(_ summary: StatsSummary) -> String {
        L10n.format("stats.summary.meta", summary.count, shared.spoken(summary.averagePerDayMinor))
    }

    /// Пометка отфильтрованного блока: «только Продукты».
    func filterMark(_ group: CategoryVizGroup) -> String {
        L10n.format("viz.drill.filter", VizText.name(group))
    }

    // MARK: - Названия периода

    /// Период словами для VoiceOver и легенды: «октябрь», «5–11 октября», «8 октября», «2026».
    func periodName(_ period: StatsPeriod, month style: DateMonthStyle = .full) -> String {
        let start = period.interval.start
        switch period.kind {
        case .month: return monthName(start)
        case .day: return style == .full ? dates.dayMonth(start) : dates.short(start)
        case .year: return yearText(start)
        case .week, nil: return dates.range(period.interval, month: style)
        }
    }

    /// Прошлый период — подпись второй кривой «Темпа»: «сентябрь», «28 сен – 4 окт», «2025».
    func previousName(_ period: StatsPeriod, month style: DateMonthStyle = .abbreviated) -> String {
        periodName(period.previous(in: calendar), month: style)
    }

    // MARK: - Столбики

    /// Подсказка и подпись оси: «Сегодня», «Вчера», «чт, 1 окт»; час — «14:00»; месяц — «Октябрь».
    func bucketTitle(_ bucket: StatsTimeBucket, step: StatsTimeStep) -> String {
        let start = bucket.interval.start
        switch step {
        case .hour: return dates.hour(start)
        case .month: return dates.monthTitle(calendar.component(.month, from: start))
        case .day, .week: return relativeDay(start) ?? dates.shortWithWeekday(start)
        }
    }

    /// `stats.days.bar.a11y`: «Сегодня, 57,20 рубля», «Четверг, 1 октября, 12 рублей».
    func bucketAccessibility(_ bucket: StatsTimeBucket, step: StatsTimeStep) -> String {
        let start = bucket.interval.start
        let title: String = switch step {
        case .hour: dates.hour(start)
        case .month: dates.monthTitle(calendar.component(.month, from: start)) + yearSuffix(start)
        case .day, .week: relativeDay(start) ?? dates.full(start)
        }
        return title + ", " + shared.spoken(bucket.totalMinor)
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
            return dates.weekdayShort(calendar.component(.weekday, from: start))
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
                let weekday = dates.weekdayShort(calendar.component(.weekday, from: date))
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
        let dayNumber = dates.dayOrdinal(currentDay.map { calendar.component(.day, from: $0.date) } ?? 0)
        var parts = [L10n.format("stats.pace.a11y")]
        if let currentDay {
            parts.append(L10n.format(
                "stats.pace.a11y.current",
                dates.capitalized(periodName(period)), shared.spoken(currentDay.cumulativeMinor), dayNumber
            ))
        }
        let previous = pace.comparison.previous
        let sameIndex = pace.comparison.current.count - 1
        let sameDay = previous.indices.contains(sameIndex) ? previous[sameIndex] : previous.last
        if let sameDay, let previousTotal = previous.last {
            let name = dates.capitalized(periodName(previousPeriod))
            // «… и 1 580 рублей за месяц» — строка есть только для месяца.
            parts.append(period.kind == .month
                ? L10n.format("stats.pace.a11y.previous", name, shared.spoken(sameDay.cumulativeMinor), dayNumber, shared.spoken(previousTotal.cumulativeMinor))
                : L10n.format("stats.pace.a11y.current", name, shared.spoken(sameDay.cumulativeMinor), dayNumber))
        }
        if let forecast = pace.forecast {
            parts.append(L10n.format("stats.pace.a11y.forecast", periodName(period), shared.spoken(forecast.roundedMinor)))
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Привычки

    /// «Пн» / «Mon»
    func weekdayShort(_ weekday: Int) -> String {
        dates.capitalized(dates.weekdayShort(weekday))
    }

    /// «Больше всего тратится **по пятницам**» / «You spend the most **on Fridays**».
    func peakWeekday(_ weekday: Int) -> AttributedString {
        L10n.attributed("stats.habits.insight.day", dates.weekdayHabit(weekday))
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
            L10n.format("stats.habits.a11y.item", dates.weekdayName(average.weekday), shared.spoken(average.averageMinor))
        }
        return L10n.format("stats.habits.a11y", items.joined(separator: L10n.format("stats.habits.a11y.separator")))
    }

    // MARK: - Год

    /// `stats.year.a11y`: «Траты за 2026 год по дням: … от 0 до 75 рублей и больше. Данные с 1 января по 8 октября».
    func yearAccessibility(_ year: StatsYearState) -> String {
        let days = year.months.flatMap { $0 }
        guard let first = days.first?.interval.start, let last = days.last?.interval.start else { return "" }
        let lastData = min(last, calendar.startOfDay(for: now))
        return L10n.format(
            "stats.year.a11y",
            String(year.year), shared.spoken(year.scale.thresholds.last ?? 0), dates.dayMonth(first), dates.dayMonth(lastData)
        )
    }

    // MARK: - Внутреннее

    /// «Сегодня» / «Вчера» (`header.title.day.*`) или `nil`.
    private func relativeDay(_ day: Date) -> String? {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day
        switch offset {
        case 0: return L10n.format("header.title.day.today")
        case -1: return L10n.format("header.title.day.yesterday")
        default: return nil
        }
    }

    /// «октябрь» / «October»
    private func monthName(_ date: Date) -> String {
        dates.monthName(calendar.component(.month, from: date))
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
