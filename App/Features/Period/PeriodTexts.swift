import Foundation
import ExpenseCore

/// Тексты шапки периода: заголовок и подписи VoiceOver (`header.*`). Даты — только через `DateTextFormatter`
/// языка интерфейса (D7 / E8).
struct PeriodTexts {
    enum Step {
        case previous, next
    }

    let formatter: any DateTextFormatter

    init(calendar: Calendar, now: Date) {
        formatter = AppLanguage.current.dateFormatter(calendar: calendar, now: now)
    }

    private var calendar: Calendar { formatter.calendar }

    /// Заголовок шапки. «Сегодня» и «Вчера» для дня — из каталога (`header.title.day.*`), остальное — D7.
    func title(for period: StatsPeriod) -> PeriodTitle {
        if period.kind == .day, let key = relativeDayKey(period.interval.start) {
            return PeriodTitle(style: .word, parts: [.init(String(localized: key))])
        }
        return formatter.title(for: period)
    }

    /// Имя кнопки-заголовка: «Период: октябрь 2026», «Свой период: 5–7 октября».
    func accessibilityLabel(for period: StatsPeriod) -> String {
        guard period.kind != nil else {
            return L10n.format("header.custom.a11y", formatter.range(period.interval, month: .full))
        }
        return L10n.format("header.month.a11y", spoken(period))
    }

    /// Стрелка ‹ или › называет период, куда перейдёт: «Предыдущий месяц, сентябрь», «Следующие 3 дня, 8–10 октября».
    func stepLabel(_ step: Step, from period: StatsPeriod) -> String {
        let target = step == .previous ? period.previous(in: calendar) : period.next(in: calendar)
        let prefix = step == .previous ? "header.prev.a11y" : "header.next.a11y"
        switch target.kind {
        case .month:
            return L10n.format(prefix, formatter.inSentence(title(for: target).text))
        case .day:
            return L10n.format(prefix + ".day", formatter.dayMonth(target.interval.start))
        case .week:
            return L10n.format(prefix + ".week", formatter.range(target.interval, month: .full))
        case .year:
            return L10n.format(prefix + ".year", title(for: target).text)
        case nil:
            let days = PeriodSelection.dayCount(of: target.interval, calendar: calendar)
            return L10n.format(prefix + ".custom", days, formatter.range(target.interval, month: .full))
        }
    }

    // MARK: - Внутреннее

    /// Период словами для VoiceOver: «октябрь 2026», «8 октября», «5–11 октября», «2026».
    private func spoken(_ period: StatsPeriod) -> String {
        let start = period.interval.start
        switch period.kind {
        case .month:
            let month = formatter.monthName(calendar.component(.month, from: start))
            return month + TextSpacing.nonBreaking + String(calendar.component(.year, from: start))
        case .day:
            return formatter.dayMonth(start)
        case .year:
            return String(calendar.component(.year, from: start))
        case .week, nil:
            return formatter.range(period.interval, month: .full)
        }
    }

    private func relativeDayKey(_ day: Date) -> String.LocalizationValue? {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: formatter.now), to: day).day
        switch offset {
        case 0: return "header.title.day.today"
        case -1: return "header.title.day.yesterday"
        default: return nil
        }
    }
}
