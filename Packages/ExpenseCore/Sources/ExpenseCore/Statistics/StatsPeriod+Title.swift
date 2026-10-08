import Foundation

extension StatsPeriod {
    /// Локализованный заголовок периода:
    /// - день — «Сегодня», «Вчера», «Завтра», иначе «6 октября»;
    /// - неделя и произвольный интервал — «6–12 окт.» (последний день — включительно);
    /// - месяц — «Октябрь 2026 г.»;
    /// - год — «2026».
    ///
    /// Для дня, недели и интервала год добавляется, только если он отличается от года `now`.
    /// Пунктуация (тире, пробелы, «г.») берётся из CLDR для `locale`.
    public func title(now: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        switch kind {
        case .day:
            dayTitle(now: now, calendar: calendar, locale: locale)
        case .week, nil:
            rangeTitle(now: now, calendar: calendar, locale: locale)
        case .month:
            Self.dateStyle(calendar: calendar, locale: locale).month(.wide).year().format(interval.start)
        case .year:
            Self.dateStyle(calendar: calendar, locale: locale).year().format(interval.start)
        }
    }

    private func dayTitle(now: Date, calendar: Calendar, locale: Locale) -> String {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: interval.start).day
        if let offset, (-1...1).contains(offset) {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.dateTimeStyle = .named
            formatter.formattingContext = .beginningOfSentence
            return formatter.localizedString(from: DateComponents(day: offset))
        }
        var style = Self.dateStyle(calendar: calendar, locale: locale).day().month(.wide)
        if calendar.component(.year, from: interval.start) != calendar.component(.year, from: now) {
            style = style.year()
        }
        return style.format(interval.start)
    }

    private func rangeTitle(now: Date, calendar: Calendar, locale: Locale) -> String {
        let firstDay = calendar.startOfDay(for: interval.start)
        let lastDay = max(firstDay, lastDayStart(calendar: calendar))
        let currentYear = calendar.component(.year, from: now)
        var style = Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day()
            .month(.abbreviated)
        if calendar.component(.year, from: firstDay) != currentYear
            || calendar.component(.year, from: lastDay) != currentYear {
            style = style.year()
        }
        return (firstDay..<lastDay).formatted(style)
    }

    /// Начало последнего дня, который задевает полуоткрытый интервал.
    private func lastDayStart(calendar: Calendar) -> Date {
        let endDayStart = calendar.startOfDay(for: interval.end)
        guard endDayStart == interval.end,
              let previousDay = calendar.date(byAdding: .day, value: -1, to: endDayStart)
        else { return endDayStart }
        return calendar.startOfDay(for: previousDay)
    }

    private static func dateStyle(calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone,
            capitalizationContext: .beginningOfSentence
        )
    }
}
