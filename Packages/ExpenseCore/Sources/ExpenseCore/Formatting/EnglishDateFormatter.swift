import Foundation

/// Даты и периоды по E8 (design/copy.en.json): свой en-US, не формат региона устройства — «Oct 8», «Thu, Oct 8»,
/// «Thursday, October 8», «Oct 5–7», «Sep 28 – Oct 4»; год — только если он не текущий («Oct 1, 2025»).
/// Неразрывный пробел — между месяцем и числом и вокруг «–» между составными датами (voice copy.en.json).
/// Падежей нет: месяц и день недели в любой фразе — одно слово, с заглавной.
public struct EnglishDateFormatter: DateTextFormatter {
    public let calendar: Calendar
    public let now: Date

    public init(calendar: Calendar, now: Date) {
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Даты

    /// «Oct 8», «Oct 8, 2025».
    public func short(_ date: Date) -> String {
        monthDay(date, .abbreviated) + (yearSuffix(for: date) ?? "")
    }

    /// «Thu, Oct 8»: день недели по-английски всегда с заглавной, `capitalized` не нужен.
    public func shortWithWeekday(_ date: Date, capitalized: Bool = false) -> String {
        weekdayShort(calendar.component(.weekday, from: date)) + ", " + short(date)
    }

    /// «October 8», «October 8, 2025» — «by October 31», «Add expense on October 8».
    public func dayMonth(_ date: Date) -> String {
        monthDay(date, .full) + (yearSuffix(for: date) ?? "")
    }

    /// «Thursday, October 8»; запасной при переполнении — «Thu, October 8».
    public func full(_ date: Date, shortWeekday: Bool = false) -> String {
        let weekday = calendar.component(.weekday, from: date)
        return (shortWeekday ? weekdayShort(weekday) : weekdayName(weekday)) + ", " + dayMonth(date)
    }

    /// Дни полуоткрытого интервала, последний — включительно: «Oct 5–7», «Sep 28 – Oct 4», «Oct 5»,
    /// «Oct 5–7, 2025». Через границу года годы — только если конец не в текущем году
    /// («Dec 28 – Jan 3», «Dec 28, 2024 – Jan 3, 2025»).
    public func range(_ interval: DateInterval, month: DateMonthStyle = .abbreviated) -> String {
        rangeParts(interval, month: month).map(\.text).joined()
    }

    /// «No expenses %1$@–%2$@»: части по обе стороны «–» — «Oct 2» и «4»; между составными датами пробелы
    /// остаются в частях: «Sep 28 » и « Oct 4».
    public func rangeBounds(_ interval: DateInterval) -> (start: String, end: String) {
        let text = range(interval)
        guard let dash = text.firstIndex(of: Self.enDash) else { return (text, "") }
        return (String(text[..<dash]), String(text[text.index(after: dash)...]))
    }

    // MARK: - Период

    /// Заголовок шапки: месяц мелко слева, числа крупно — «Oct» + « 5–7», «Sep» + « 28 – » + «Oct» + « 4»;
    /// «October» (+ «2025», если год не текущий); «2026». «Today» и «Yesterday» дня — из каталога (App).
    public func title(for period: StatsPeriod) -> PeriodTitle {
        let start = period.interval.start
        switch period.kind {
        case .month:
            var parts = [PeriodTitle.Part(monthTitle(calendar.component(.month, from: start)))]
            if yearSuffix(for: start) != nil {
                parts.append(.init(TextSpacing.nonBreaking + String(calendar.component(.year, from: start)), isSecondary: true))
            }
            return PeriodTitle(style: .word, parts: parts)
        case .year:
            return PeriodTitle(style: .word, parts: [.init(String(calendar.component(.year, from: start)))])
        case .day, .week, nil:
            return PeriodTitle(style: .dates, parts: rangeParts(period.interval, month: .abbreviated))
        }
    }

    /// «by Sunday» (последний день недели по `calendar.firstWeekday`), «by October 31», «by December 31».
    /// `nil` — у «Дня» и своего периода темпа нет.
    public func paceTarget(for period: StatsPeriod) -> String? {
        let lastDay = lastDayStart(of: period.interval)
        switch period.kind {
        case .week: return weekdayName(calendar.component(.weekday, from: lastDay))
        case .month, .year: return dayMonth(lastDay)
        case .day, nil: return nil
        }
    }

    /// Начало часа: «9:00», «14:00» — как у оси «По часам» (номер часа).
    public func hour(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return "\(parts.hour ?? 0):" + String(format: "%02d", parts.minute ?? 0)
    }

    /// «as of the 8th»: 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st, 22nd, 23rd … 31st.
    public func dayOrdinal(_ day: Int) -> String {
        let suffix = switch (day % 100, day % 10) {
        case (11...13, _): "th"
        case (_, 1): "st"
        case (_, 2): "nd"
        case (_, 3): "rd"
        default: "th"
        }
        return "\(day)\(suffix)"
    }

    // MARK: - Слова

    /// «October»
    public func monthName(_ month: Int) -> String {
        Self.months[Self.index(month, in: 1...12)]
    }

    /// «October»
    public func monthTitle(_ month: Int) -> String {
        monthName(month)
    }

    /// «August» — «in August».
    public func monthInPhrase(_ month: Int) -> String {
        monthName(month)
    }

    /// «Oct», «Sep», «May».
    public func monthShort(_ month: Int) -> String {
        Self.monthsShort[Self.index(month, in: 1...12)]
    }

    /// «Thursday»
    public func weekdayName(_ weekday: Int) -> String {
        Self.weekdays[Self.index(weekday, in: 1...7)]
    }

    /// «Thu»
    public func weekdayShort(_ weekday: Int) -> String {
        Self.weekdaysShort[Self.index(weekday, in: 1...7)]
    }

    /// «on Fridays»
    public func weekdayHabit(_ weekday: Int) -> String {
        "on " + weekdayName(weekday) + "s"
    }

    /// По-английски регистр внутри фразы не меняется: «September 2025».
    public func inSentence(_ title: String) -> String {
        title
    }

    // MARK: - Внутреннее

    private static let enDash: Character = "\u{2013}"

    /// «Oct 8», «October 8» — без года.
    private func monthDay(_ date: Date, _ style: DateMonthStyle) -> String {
        let parts = calendar.dateComponents([.day, .month], from: date)
        return monthText(parts.month ?? 1, style) + TextSpacing.nonBreaking + "\(parts.day ?? 0)"
    }

    private func monthText(_ month: Int, _ style: DateMonthStyle) -> String {
        style == .full ? monthName(month) : monthShort(month)
    }

    /// «, 2025», если год даты не текущий.
    private func yearSuffix(for date: Date) -> String? {
        let year = calendar.component(.year, from: date)
        return year == calendar.component(.year, from: now) ? nil : ", " + String(year)
    }

    private func rangeParts(_ interval: DateInterval, month style: DateMonthStyle) -> [PeriodTitle.Part] {
        let first = calendar.startOfDay(for: interval.start)
        let last = max(first, lastDayStart(of: interval))
        let from = calendar.dateComponents([.year, .month, .day], from: first)
        let to = calendar.dateComponents([.year, .month, .day], from: last)
        let (fromDay, toDay) = (from.day ?? 1, to.day ?? 1)
        let (fromMonth, toMonth) = (monthText(from.month ?? 1, style), monthText(to.month ?? 1, style))
        let space = TextSpacing.nonBreaking
        let dash = space + String(Self.enDash) + space

        guard from.year == to.year else {
            // Через границу года: годы — только если конец не в текущем году.
            let showsYears = yearSuffix(for: last) != nil
            var parts: [PeriodTitle.Part] = [.init(fromMonth, isSecondary: true), .init(space + "\(fromDay)")]
            if showsYears { parts.append(.init(", " + String(from.year ?? 0), isSecondary: true)) }
            parts += [.init(dash), .init(toMonth, isSecondary: true), .init(space + "\(toDay)")]
            if showsYears { parts.append(.init(", " + String(to.year ?? 0), isSecondary: true)) }
            return parts
        }
        var parts: [PeriodTitle.Part]
        if from == to {
            parts = [.init(toMonth, isSecondary: true), .init(space + "\(toDay)")]
        } else if from.month == to.month {
            parts = [.init(toMonth, isSecondary: true), .init(space + "\(fromDay)" + String(Self.enDash) + "\(toDay)")]
        } else {
            parts = [.init(fromMonth, isSecondary: true), .init(space + "\(fromDay)" + dash),
                     .init(toMonth, isSecondary: true), .init(space + "\(toDay)")]
        }
        if let year = yearSuffix(for: last) { parts.append(.init(year, isSecondary: true)) }
        return parts
    }

    /// Начало последнего дня, который задевает полуоткрытый интервал.
    private func lastDayStart(of interval: DateInterval) -> Date {
        let endDayStart = calendar.startOfDay(for: interval.end)
        guard endDayStart == interval.end,
              let previousDay = calendar.date(byAdding: .day, value: -1, to: endDayStart)
        else { return endDayStart }
        return calendar.startOfDay(for: previousDay)
    }

    private static func index(_ value: Int, in range: ClosedRange<Int>) -> Int {
        precondition(range.contains(value), "Значение вне \(range): \(value)")
        return value - range.lowerBound
    }

    private static let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    /// Три буквы, как `stats.year.months` в copy.en.json («Sep», не «Sept»).
    private static let monthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// Нумерация `Calendar`: 1 — воскресенье … 7 — суббота.
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let weekdaysShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
}
