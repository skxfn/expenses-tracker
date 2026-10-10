import Foundation
import Observation
import ExpenseCore

/// Состояние вкладки «Календарь» (макет 09): месяц, выбранный день и всё, что из них считается
/// по тратам. Траты приходят снимками `ExpenseRecord` из `@Query` экрана — уже без строк,
/// скрытых `PendingDeletion`. Изменений данных здесь нет: только чтение.
@Observable
final class CalendarModel {
    /// День в сетке.
    struct Day: Hashable {
        let date: Date
        let totalMinor: Int64
        /// Ступень шкалы heat 0…4.
        let level: Int
        let isToday: Bool
        /// Ещё не наступил: без клетки, число серым.
        let isFuture: Bool

        /// Будущий день без трат не выбирается (клетки нет, записывать в будущее нечего).
        var isSelectable: Bool { !isFuture || totalMinor > 0 }
    }

    /// Строка-итог месяца (`cal.summary`).
    struct Summary: Hashable {
        let totalMinor: Int64
        /// Дней месяца по сегодня включительно (прошедший месяц — все дни).
        let dayCount: Int
        /// День с наибольшей суммой; `nil` — трат в месяце нет.
        let peakDay: Date?
    }

    let calendar: Calendar
    private(set) var month: MonthGrid
    private(set) var selectedDay: Date
    private(set) var now: Date
    private(set) var summary = Summary(totalMinor: 0, dayCount: 0, peakDay: nil)
    /// Шкала года отображаемого месяца — одна с тепловой картой статистики; `nil` — в году трат нет.
    private(set) var heatScale: StatsHeatScale?
    /// Категории верхнего уровня месяца по убыванию суммы (для ауры).
    private(set) var topGroupIDs: [UUID] = []

    private var dailyTotals: [Date: Int64] = [:]
    private var records: [ExpenseRecord] = []

    init(calendar: Calendar = .autoupdatingCurrent, now: Date = .now) {
        self.calendar = calendar
        self.now = now
        month = MonthGrid(containing: now, calendar: calendar)
        selectedDay = calendar.startOfDay(for: now)
    }

    // MARK: Данные

    /// Новые траты или новое «сейчас» (смена суток, возврат из фона).
    func update(records: [ExpenseRecord], now: Date) {
        self.records = records
        self.now = now
        recompute()
        // Выбранный день мог оказаться в будущем (смена часового пояса, удалённая будущая трата).
        if !day(selectedDay).isSelectable {
            selectedDay = month.day(matching: selectedDay, notAfter: now)
        }
    }

    func day(_ date: Date) -> Day {
        let total = dailyTotals[date] ?? 0
        let today = calendar.startOfDay(for: now)
        return Day(
            date: date,
            totalMinor: total,
            level: heatScale?.level(forMinor: total) ?? 0,
            isToday: date == today,
            isFuture: date > today
        )
    }

    var selected: Day { day(selectedDay) }

    /// Попадает ли момент в выбранный день — фильтр трат листа дня.
    func isInSelectedDay(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDay)
    }

    /// Дата для «Записать на …»: `nil` — сегодня (как «+»), иначе выбранный день с текущим временем,
    /// чтобы записи одного дня шли в порядке ввода.
    var entryDateForSelectedDay: Date? {
        guard !calendar.isDate(selectedDay, inSameDayAs: now) else { return nil }
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(
            bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: selectedDay
        ) ?? selectedDay
    }

    // MARK: Навигация

    var isCurrentMonth: Bool { month.contains(now) }

    /// › неактивна, если следующий месяц целиком в будущем (как `canShowNext` статистики).
    var canShowNext: Bool { month.period.interval.end <= now }

    func showPrevious() {
        show(month.previous())
    }

    func showNext() {
        guard canShowNext else { return }
        show(month.next())
    }

    /// Последняя трата вне показанного месяца, когда в нём трат нет — для «К последней трате»
    /// (INTEGRATION §2.2, «Период без трат»); иначе `nil`.
    var latestExpenseOutsideEmptyMonth: Date? {
        guard summary.totalMinor == 0, let latest = records.map(\.date).max(), !month.contains(latest) else { return nil }
        return latest
    }

    /// Открыть месяц последней траты и выбрать её день.
    func showLatestExpense() {
        guard let latest = latestExpenseOutsideEmptyMonth else { return }
        month = MonthGrid(containing: latest, calendar: calendar)
        selectedDay = calendar.startOfDay(for: latest)
        recompute()
    }

    /// Выбрать день; будущий день без трат не выбирается.
    func select(_ date: Date) {
        guard month.contains(date), day(date).isSelectable else { return }
        selectedDay = calendar.startOfDay(for: date)
    }

    // MARK: Внутреннее

    /// В новом месяце выбран день с тем же числом, но не позже сегодня.
    private func show(_ newMonth: MonthGrid) {
        month = newMonth
        selectedDay = newMonth.day(matching: selectedDay, notAfter: now)
        recompute()
    }

    private func recompute() {
        let engine = StatisticsEngine(calendar: calendar)
        let series = engine.timeSeries(for: month.period, records: records, step: .day)
        dailyTotals = Dictionary(
            series.buckets.map { (calendar.startOfDay(for: $0.interval.start), $0.totalMinor) },
            uniquingKeysWith: +
        )
        let monthSummary = engine.summary(for: month.period, records: records, now: now)
        summary = Summary(
            totalMinor: monthSummary.totalMinor,
            dayCount: monthSummary.averagedDayCount,
            peakDay: series.peak.map { calendar.startOfDay(for: $0.interval.start) }
        )
        heatScale = engine.heatScale(forYearContaining: month.start, records: records)
        topGroupIDs = engine.groupBreakdown(for: month.period, records: records).compactMap(\.groupID)
    }
}
