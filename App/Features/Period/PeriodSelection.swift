import Foundation
import Observation
import SwiftUI
import ExpenseCore

/// Пункт сегмента периода: «День · Неделя · Месяц · Год · Свой».
enum PeriodMode: Hashable, CaseIterable {
    case day, week, month, year, custom

    init(_ kind: StatsPeriodKind) {
        switch kind {
        case .day: self = .day
        case .week: self = .week
        case .month: self = .month
        case .year: self = .year
        }
    }

    /// Календарный вид; `nil` — свой период.
    var kind: StatsPeriodKind? {
        switch self {
        case .day: .day
        case .week: .week
        case .month: .month
        case .year: .year
        case .custom: nil
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .day: "period.segment.day"
        case .week: "period.segment.week"
        case .month: "period.segment.month"
        case .year: "period.segment.year"
        case .custom: "period.segment.custom"
        }
    }
}

/// Выбранный период — общий для главной и статистики (INTEGRATION §4.7). Каждый экран держит свой экземпляр:
/// период на вкладках независим. Переход «плитка → статистика» передаёт период через
/// `AppRouter.statisticsFocus`, статистика применяет его сама: `selection.apply(focus.period)`.
///
/// Свой период — дни целиком, `[начало первого дня, начало дня после последнего)`; ‹ › шагают на его длину.
/// `now` и календарь инжектируются (тесты, скриншоты); `refresh(now:)` вызывает `PeriodHeader` при появлении,
/// возвращении приложения из фона и смене дня (`onCalendarDayChange`).
///
///     @State private var period = PeriodSelection()            // месяц, сегодня
///     PeriodHeader(selection: period)                           // «Октябрь ▾», ‹ ›, ⚙
///     PeriodSegment(selection: period)
///     // данные: period.period (StatsPeriod), period.now, period.calendar
@Observable
final class PeriodSelection {
    let calendar: Calendar
    private(set) var now: Date
    private(set) var period: StatsPeriod
    /// Последний свой диапазон: «Свой» в сегменте возвращается к нему. `nil` — ещё не выбирали.
    private(set) var customInterval: DateInterval?
    /// Шит «Период» (▾ в шапке, «Свой» без диапазона или повторный тап по «Свой»).
    var isPickerPresented = false

    init(kind: StatsPeriodKind = .month, calendar: Calendar = .autoupdatingCurrent, now: Date = .now) {
        self.calendar = calendar
        self.now = now
        period = .current(kind, now: now, calendar: calendar)
    }

    // MARK: - Состояние

    var mode: PeriodMode { period.kind.map(PeriodMode.init) ?? .custom }

    /// Сегодня внутри периода. Вне его показывается чип «Сегодня» (§8 п. 17).
    var isCurrent: Bool { period.contains(now) }

    /// › неактивна, если следующий период целиком в будущем (DESIGN.md → Custom Period).
    var canShowNext: Bool { period.interval.end <= now }

    /// Длина периода в календарных днях (подписи своего периода).
    var dayCount: Int { Self.dayCount(of: period.interval, calendar: calendar) }

    /// Начало сегодняшнего дня.
    var today: Date { calendar.startOfDay(for: now) }

    /// Даты и периоды (D7 / E8 — по языку интерфейса) для текущего `now`.
    var dateFormatter: any DateTextFormatter { AppLanguage.current.dateFormatter(calendar: calendar, now: now) }

    // MARK: - Действия

    /// Пункт сегмента. Календарный вид остаётся рядом с просматриваемым периодом, а не прыгает в сегодня;
    /// «Свой» возвращает последний диапазон, без него — и при повторном тапе — открывает шит.
    func select(_ mode: PeriodMode) {
        guard let kind = mode.kind else {
            if self.mode != .custom, let customInterval {
                period = .custom(customInterval)
            } else {
                presentPicker()
            }
            return
        }
        guard mode != self.mode else { return }
        let anchor = isCurrent ? now : period.interval.start
        period = .current(kind, now: anchor, calendar: calendar)
    }

    func showPrevious() {
        setPeriod(period.previous(in: calendar))
    }

    func showNext() {
        guard canShowNext else { return }
        setPeriod(period.next(in: calendar))
    }

    /// Чип «Сегодня»: календарный период с сегодняшним днём; свой — диапазон той же длины, кончающийся сегодня.
    func showCurrent() {
        guard let kind = period.kind else {
            let days = max(dayCount, 1)
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
            applyCustom(from: start, through: today)
            return
        }
        setPeriod(.current(kind, now: now, calendar: calendar))
    }

    /// Готовый период: из шита «Период» или `StatisticsFocus`.
    func apply(_ period: StatsPeriod) {
        setPeriod(period)
    }

    /// Свой период по дням включительно (порядок дней не важен).
    func applyCustom(from firstDay: Date, through lastDay: Date) {
        apply(.custom(Self.dayInterval(from: firstDay, through: lastDay, calendar: calendar)))
    }

    func presentPicker() {
        isPickerPresented = true
    }

    /// Обновить «сейчас» при смене дня (периоды и сравнения считаются днями — чаще не пересчитываем).
    /// Если смотрели текущий период, переходим в новый текущий.
    func refresh(now: Date = .now) {
        guard !calendar.isDate(now, inSameDayAs: self.now) else { return }
        let wasCurrent = isCurrent
        self.now = now
        if wasCurrent, !isCurrent {
            showCurrent()
        }
    }

    // MARK: - Внутреннее

    private func setPeriod(_ period: StatsPeriod) {
        self.period = period
        if period.kind == nil {
            customInterval = period.interval
        }
    }

    /// Дни включительно → полуоткрытый интервал `[начало первого, начало дня после последнего)`.
    static func dayInterval(from firstDay: Date, through lastDay: Date, calendar: Calendar) -> DateInterval {
        let first = calendar.startOfDay(for: min(firstDay, lastDay))
        let last = calendar.startOfDay(for: max(firstDay, lastDay))
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return DateInterval(start: first, end: end)
    }

    /// Число календарных дней, которые задевает полуоткрытый интервал.
    static func dayCount(of interval: DateInterval, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: interval.start)
        let days = calendar.dateComponents([.day], from: start, to: interval.end).day ?? 0
        let endsAtMidnight = calendar.startOfDay(for: interval.end) == interval.end
        return max(endsAtMidnight ? days : days + 1, 1)
    }
}
