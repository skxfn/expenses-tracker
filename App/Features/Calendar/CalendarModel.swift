import Foundation
import Observation
import ExpenseCore

/// Состояние вкладки «Календарь» (макет 09): месяц, выбранный день и всё, что из них считается
/// по тратам. Траты модель выбирает из хранилища сама и только нужные: год показанного месяца
/// (шкала heat — по году) снимками `ExpenseRecord` и строки выбранного дня; заново — когда данные
/// сохранены (`dataDidChange`; пока вкладку не видно — при следующем появлении), сменился год или день.
/// Строки, скрытые `PendingDeletion`, не учитываются.
/// Изменений данных здесь нет: только чтение.
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
    private var store: ExpenseStore?
    private var hiddenIDs: Set<UUID> = []
    /// Траты года показанного месяца (вместе со скрытыми) и какой это год.
    private var yearRecords: [ExpenseRecord] = []
    private var loadedYear: DateInterval?
    /// Дата последней траты вообще, без скрытых, — для «К последней трате».
    private var latestExpenseDate: Date?
    /// Строки выбранного дня (вместе со скрытыми), новые сверху.
    private var selectedDayRows: [ExpenseRowData] = []
    /// База менялась после последнего чтения (или ещё не читалась).
    @ObservationIgnored private var isStale = true
    @ObservationIgnored private var isVisible = false

    init(calendar: Calendar = .autoupdatingCurrent, now: Date = .now) {
        self.calendar = calendar
        self.now = now
        month = MonthGrid(containing: now, calendar: calendar)
        selectedDay = calendar.startOfDay(for: now)
    }

    // MARK: Данные

    /// Экран появился: подключить хранилище; траты выбрать заново, только если база менялась, пока его не было видно.
    func appear(_ store: ExpenseStore, hiddenIDs: Set<UUID>, now: Date = .now) {
        self.store = store
        isVisible = true
        if isStale {
            self.hiddenIDs = hiddenIDs
            reload(now: now)
        } else {
            setHiddenIDs(hiddenIDs)
            refresh(now: now)
        }
    }

    func disappear() {
        isVisible = false
    }

    /// Данные сохранены (`ModelContext.didSave`): на виду — выбрать траты заново сразу, иначе — при появлении.
    func dataDidChange(now: Date = .now) {
        isStale = true
        if isVisible { reload(now: now) }
    }

    private func reload(now: Date) {
        isStale = false
        advance(to: now)
        loadYear(force: true)
        loadLatestExpense()
        finishUpdate()
    }

    /// Новое «сейчас» без новых данных: возврат из фона, смена дня (`onCalendarDayChange`).
    func refresh(now: Date = .now) {
        advance(to: now)
        loadYear(force: false)
        finishUpdate()
    }

    /// Строки, которые ждут удаления (`PendingDeletion`), скрываются сразу — хранилище ещё не изменилось.
    func setHiddenIDs(_ ids: Set<UUID>) {
        guard ids != hiddenIDs else { return }
        hiddenIDs = ids
        loadLatestExpense()
        recompute()
    }

    /// Строки листа выбранного дня, новые сверху.
    var dayRows: [ExpenseRowData] {
        selectedDayRows.filter { !hiddenIDs.contains($0.id) }
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
        guard summary.totalMinor == 0, let latest = latestExpenseDate, !month.contains(latest) else { return nil }
        return latest
    }

    /// Открыть месяц последней траты и выбрать её день.
    func showLatestExpense() {
        guard let latest = latestExpenseOutsideEmptyMonth else { return }
        month = MonthGrid(containing: latest, calendar: calendar)
        selectedDay = calendar.startOfDay(for: latest)
        loadYear(force: false)
        recompute()
        loadSelectedDay()
    }

    /// Выбрать день; будущий день без трат не выбирается.
    func select(_ date: Date) {
        guard month.contains(date), day(date).isSelectable else { return }
        selectedDay = calendar.startOfDay(for: date)
        loadSelectedDay()
    }

    // MARK: Внутреннее

    /// В новом месяце выбран день с тем же числом, но не позже сегодня.
    private func show(_ newMonth: MonthGrid) {
        month = newMonth
        selectedDay = newMonth.day(matching: selectedDay, notAfter: now)
        loadYear(force: false)
        recompute()
        loadSelectedDay()
    }

    /// Новое «сейчас»; если наступили новые сутки — текущий месяц и «сегодня» сдвигаются
    /// (`MonthGrid.rolledOver`).
    private func advance(to now: Date) {
        let previous = self.now
        self.now = now
        guard !calendar.isDate(now, inSameDayAs: previous) else { return }
        let rolled = month.rolledOver(selected: selectedDay, from: previous, to: now)
        month = rolled.month
        selectedDay = rolled.selected
    }

    private func finishUpdate() {
        recompute()
        // Выбранный день мог оказаться в будущем (смена часового пояса, удалённая будущая трата).
        if !day(selectedDay).isSelectable {
            selectedDay = month.day(matching: selectedDay, notAfter: now)
        }
        loadSelectedDay()
    }

    /// Траты года показанного месяца — только при смене года или `force` (данные сохранены).
    /// Ошибка выборки — пустой календарь, как пустой `@Query`.
    private func loadYear(force: Bool) {
        let year = StatsPeriod.current(.year, now: month.start, calendar: calendar).interval
        guard let store, force || year != loadedYear else { return }
        yearRecords = ((try? store.expenses(in: year)) ?? []).map { ExpenseRecord($0) }
        loadedYear = year
    }

    private func loadLatestExpense() {
        let recent = (try? store?.recentExpenses(limit: hiddenIDs.count + 1)) ?? []
        latestExpenseDate = recent.first { !hiddenIDs.contains($0.id) }?.date
    }

    private func loadSelectedDay() {
        guard let store, let interval = calendar.dateInterval(of: .day, for: selectedDay) else {
            selectedDayRows = []
            return
        }
        selectedDayRows = ((try? store.expenses(in: interval)) ?? []).map { ExpenseRowData($0) }
    }

    private func recompute() {
        let records = hiddenIDs.isEmpty ? yearRecords : yearRecords.filter { !hiddenIDs.contains($0.id) }
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
