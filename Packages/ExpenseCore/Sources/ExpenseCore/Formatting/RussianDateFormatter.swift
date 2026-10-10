import Foundation

/// Даты и периоды по D7 (design/copy.json): свои короткие формы без точки, год — только если он
/// не текущий (год `now`), неразрывный пробел внутри даты. Локали нет: формы — из `RussianWords`,
/// календарь (часовой пояс, первый день недели) — снаружи. Английский — `EnglishDateFormatter`.
public struct RussianDateFormatter: DateTextFormatter {
    public typealias MonthStyle = DateMonthStyle

    public let calendar: Calendar
    public let now: Date

    public init(calendar: Calendar, now: Date) {
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Даты

    /// «8 окт», «8 окт 2025».
    public func short(_ date: Date) -> String {
        dayAndMonth(date, .abbreviated)
    }

    /// «чт, 8 окт»; в начале строки — «Чт, 8 окт».
    public func shortWithWeekday(_ date: Date, capitalized: Bool = false) -> String {
        let weekday = RussianWords.weekday(calendar.component(.weekday, from: date), .abbreviated)
        return (capitalized ? RussianWords.capitalized(weekday) : weekday) + ", " + short(date)
    }

    /// «8 октября», «8 октября 2025» — «к 31 октября», «Записать трату на 8 октября».
    public func dayMonth(_ date: Date) -> String {
        dayAndMonth(date, .full)
    }

    /// «Четверг, 8 октября» — как системный wide-формат, но с U+00A0 внутри даты и без «г.» у года.
    /// - Parameter shortWeekday: запасной вариант при переполнении — «Вс, 30 сентября».
    public func full(_ date: Date, shortWeekday: Bool = false) -> String {
        let weekday = calendar.component(.weekday, from: date)
        let name = RussianWords.weekday(weekday, shortWeekday ? .abbreviated : .nominative)
        return RussianWords.capitalized(name) + ", " + dayMonth(date)
    }

    /// Дни полуоткрытого интервала, последний — включительно: «5–7 окт», «28 сен – 4 окт», «5 окт».
    /// Через границу года годы не пишутся, если конец в текущем году («28 дек – 3 янв»).
    public func range(_ interval: DateInterval, month: MonthStyle = .abbreviated) -> String {
        rangeParts(interval, month: month).map(\.text).joined()
    }

    // MARK: - Период

    /// Заголовок шапки: «Сегодня», «Вчера», «6 окт»; «5–11 окт», «28 сен – 4 окт»;
    /// «Октябрь» (+ «2025», если год не текущий); «2026»; свой период — как неделя.
    public func title(for period: StatsPeriod) -> PeriodTitle {
        let start = period.interval.start
        switch period.kind {
        case .day:
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: start).day
            switch offset {
            case 0: return PeriodTitle(style: .word, parts: [.init("Сегодня")])
            case -1: return PeriodTitle(style: .word, parts: [.init("Вчера")])
            default: return PeriodTitle(style: .dates, parts: rangeParts(period.interval, month: .abbreviated))
            }
        case .month:
            let month = RussianWords.capitalized(RussianWords.month(calendar.component(.month, from: start), .nominative))
            var parts = [PeriodTitle.Part(month)]
            if let year = yearSuffix(for: start) { parts.append(.init(year, isSecondary: true)) }
            return PeriodTitle(style: .word, parts: parts)
        case .year:
            return PeriodTitle(style: .word, parts: [.init(String(calendar.component(.year, from: start)))])
        case .week, nil:
            return PeriodTitle(style: .dates, parts: rangeParts(period.interval, month: .abbreviated))
        }
    }

    /// С чем сравнили (D5): «вчера», «накануне», «на прошлой неделе», «в прошлом месяце»,
    /// «в прошлом году», «в августе», «в 2024», «за 2–4 окт». Вставляется в «чем …», «примерно как …»,
    /// «… трат не было».
    public func comparisonReference(_ reference: StatsComparisonReference) -> String {
        switch reference {
        case .yesterday: "вчера"
        case .dayBefore: "накануне"
        case .lastWeek: "на прошлой неделе"
        case .lastMonth: "в прошлом месяце"
        case .lastYear: "в прошлом году"
        case .month(let month): "в " + RussianWords.month(month, .prepositional)
        case .year(let year): "в \(year)"
        case .range(let interval): "за " + range(interval)
        }
    }

    /// К чему прогноз, в дательном без предлога (предлог — в строке `stats.pace.note` «к %@ при текущем темпе»):
    /// неделя — «воскресенью» (последний день недели по `calendar.firstWeekday`), месяц и год — «31 октября»,
    /// «31 декабря». `nil` — у «Дня» и своего периода темпа нет.
    public func paceTarget(for period: StatsPeriod) -> String? {
        let lastDay = lastDayStart(of: period.interval)
        switch period.kind {
        case .week: return RussianWords.weekday(calendar.component(.weekday, from: lastDay), .dativeSingular)
        case .month, .year: return dayMonth(lastDay)
        case .day, nil: return nil
        }
    }

    /// Начало часа: «9:00», «14:00» — подписи вида «День» («По часам»).
    public func hour(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return "\(parts.hour ?? 0):" + String(format: "%02d", parts.minute ?? 0)
    }

    /// «С %1$@ по %2$@ трат не было»: «2» и «4 окт», «28 сен» и «4 окт» — месяц у начала, только если он другой.
    public func rangeBounds(_ interval: DateInterval) -> (start: String, end: String) {
        let first = calendar.startOfDay(for: interval.start)
        let last = max(first, lastDayStart(of: interval))
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        return (sameMonth ? String(calendar.component(.day, from: first)) : short(first), short(last))
    }

    /// «к 8 числу»: число как есть.
    public func dayOrdinal(_ day: Int) -> String {
        String(day)
    }

    // MARK: - Слова

    /// «октябрь»
    public func monthName(_ month: Int) -> String {
        RussianWords.month(month, .nominative)
    }

    /// «Октябрь»
    public func monthTitle(_ month: Int) -> String {
        RussianWords.capitalized(RussianWords.month(month, .nominative))
    }

    /// «августе» — «в августе».
    public func monthInPhrase(_ month: Int) -> String {
        RussianWords.month(month, .prepositional)
    }

    /// «окт»
    public func monthShort(_ month: Int) -> String {
        RussianWords.month(month, .abbreviated)
    }

    /// «четверг»
    public func weekdayName(_ weekday: Int) -> String {
        RussianWords.weekday(weekday, .nominative)
    }

    /// «чт»
    public func weekdayShort(_ weekday: Int) -> String {
        RussianWords.weekday(weekday, .abbreviated)
    }

    /// «по пятницам»
    public func weekdayHabit(_ weekday: Int) -> String {
        "по " + RussianWords.weekday(weekday, .dativePlural)
    }

    /// «Сентябрь 2025» → «сентябрь 2025».
    public func inSentence(_ title: String) -> String {
        title.lowercased()
    }

    // MARK: - Внутреннее

    private static let enDash = "\u{2013}"

    private func dayAndMonth(_ date: Date, _ style: MonthStyle) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        return "\(parts.day ?? 0)" + monthText(parts.month ?? 1, style) + (yearSuffix(for: date) ?? "")
    }

    private func monthText(_ month: Int, _ style: MonthStyle) -> String {
        TextSpacing.nonBreaking + RussianWords.month(month, style == .full ? .genitive : .abbreviated)
    }

    /// « 2025» (с U+00A0), если год даты не текущий.
    private func yearSuffix(for date: Date) -> String? {
        let year = calendar.component(.year, from: date)
        return year == calendar.component(.year, from: now) ? nil : TextSpacing.nonBreaking + String(year)
    }

    private func rangeParts(_ interval: DateInterval, month style: MonthStyle) -> [PeriodTitle.Part] {
        let first = calendar.startOfDay(for: interval.start)
        let last = max(first, lastDayStart(of: interval))
        let from = calendar.dateComponents([.year, .month, .day], from: first)
        let to = calendar.dateComponents([.year, .month, .day], from: last)
        let (fromDay, toDay) = (from.day ?? 1, to.day ?? 1)
        let (fromMonth, toMonth) = (monthText(from.month ?? 1, style), monthText(to.month ?? 1, style))
        let dash = TextSpacing.nonBreaking + Self.enDash + " "

        guard from.year == to.year else {
            // Через границу года: годы — только если конец не в текущем году.
            let showsYears = yearSuffix(for: last) != nil
            return [
                .init("\(fromDay)"),
                .init(fromMonth + (showsYears ? TextSpacing.nonBreaking + String(from.year ?? 0) : ""), isSecondary: true),
                .init(dash + "\(toDay)"),
                .init(toMonth + (showsYears ? TextSpacing.nonBreaking + String(to.year ?? 0) : ""), isSecondary: true)
            ]
        }
        let year = yearSuffix(for: last) ?? ""
        if from == to {
            return [.init("\(fromDay)"), .init(toMonth + year, isSecondary: true)]
        }
        if from.month == to.month {
            return [.init("\(fromDay)" + Self.enDash + "\(toDay)"), .init(toMonth + year, isSecondary: true)]
        }
        return [
            .init("\(fromDay)"),
            .init(fromMonth, isSecondary: true),
            .init(dash + "\(toDay)"),
            .init(toMonth + year, isSecondary: true)
        ]
    }

    /// Начало последнего дня, который задевает полуоткрытый интервал.
    private func lastDayStart(of interval: DateInterval) -> Date {
        let endDayStart = calendar.startOfDay(for: interval.end)
        guard endDayStart == interval.end,
              let previousDay = calendar.date(byAdding: .day, value: -1, to: endDayStart)
        else { return endDayStart }
        return calendar.startOfDay(for: previousDay)
    }
}
