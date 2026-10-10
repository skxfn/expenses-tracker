import Foundation
import ExpenseCore

/// Тексты главной: заголовки дней (`feed.dayHeader.*`) и подписи VoiceOver; сравнение, пустой период
/// и озвучка сумм — общие со статистикой (`shared`). Ключи — из каталога, данные — форматтеры Core:
/// суммы — `MoneyFormatter.Style`, даты — `DateTextFormatter` языка интерфейса (D7 / E8), озвучка сумм — `a11y.money`.
struct HomeTexts {
    let money: MoneyFormatter
    let dates: any DateTextFormatter
    let shared: SummaryTexts

    init(money: MoneyFormatter, calendar: Calendar, now: Date) {
        self.money = money
        dates = AppLanguage.current.dateFormatter(calendar: calendar, now: now)
        shared = SummaryTexts(money: money, dates: dates)
    }

    private var calendar: Calendar { dates.calendar }

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
        let weekday = dates.weekdayName(calendar.component(.weekday, from: day))
        let date: String = switch dayOffset(day) {
        case 0: [String(localized: "header.title.day.today"), weekday, dates.dayMonth(day)].joined(separator: ", ")
        case -1: [String(localized: "header.title.day.yesterday"), weekday, dates.dayMonth(day)].joined(separator: ", ")
        default: dates.full(day)
        }
        return date + ", " + shared.spoken(totalMinor)
    }

    // MARK: - VoiceOver

    /// Период для подписей «Итог и траты за …», «Траты за … по категориям»:
    /// «октябрь», «2026», «8 октября», «5–7 октября».
    func periodName(_ period: StatsPeriod) -> String {
        let start = period.interval.start
        switch period.kind {
        case .month:
            let month = dates.monthName(calendar.component(.month, from: start))
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

    // MARK: - Внутреннее

    /// 0 — сегодня, −1 — вчера.
    private func dayOffset(_ day: Date) -> Int {
        let today = calendar.startOfDay(for: dates.now)
        return calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day)).day ?? .min
    }
}
