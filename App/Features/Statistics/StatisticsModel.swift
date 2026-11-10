import Foundation
import Observation
import SwiftData
import ExpenseCore

/// Входные данные статистики: снимок каталога (без SwiftData), период, раскрытая категория и скрытые траты.
/// Сами траты модель читает из базы сама (`appear(in:)`, `dataDidChange(in:)`).
struct StatisticsInput: Equatable {
    var catalog = CategoryCatalogSnapshot([])
    var period: StatsPeriod
    var now: Date
    /// Выбор в разделе «Категории» (категория, подкатегория, «Без категории»): фильтрует сводку, журнал
    /// и все остальные блоки; категория с подкатегориями раскрывается до них.
    var selection: StatsCategorySelection?
    /// Траты, помеченные на удаление (`PendingDeletion.hiddenIDs`): ещё в базе, но в расчёт не идут.
    var hiddenIDs: Set<UUID> = []
}

/// «Темп»: прогноз идущего периода (`forecast`) или итог прошедшего и накопительные кривые.
struct StatsPaceState: Equatable {
    let comparison: StatsCumulativeComparison
    /// `nil` — период прошёл: вместо прогноза итог.
    let forecast: StatsForecast?
    let totalMinor: Int64
    /// Дней в периоде — длина оси.
    let dayCount: Int
    let hasEnoughData: Bool
}

/// «Привычки»: средние по дням недели, выводы и шкала heat года.
struct StatsHabitsState: Equatable {
    let habits: StatsHabits
    let scale: StatsHeatScale?
    let hasEnoughData: Bool
}

/// «2026 по дням»: дни года по месяцам и общая с календарём шкала heat.
struct StatsYearState: Equatable {
    let year: Int
    let months: [[StatsTimeBucket]]
    let scale: StatsHeatScale
}

/// Журнал выбранной категории: начало ленты её трат за период (дни целиком) и сколько трат всего.
struct StatsJournalState {
    let days: [HomeFeedDay]
    /// Трат выбранной категории за период.
    let count: Int

    /// Сколько трат не поместилось в начало журнала — «Ещё 40 трат».
    var hiddenCount: Int { count - days.reduce(0) { $0 + $1.rows.count } }
}

/// Расчёты вкладки «Статистика» (INTEGRATION §4.6–4.8). Все суммы считает `StatisticsEngine`; модель
/// выбирает, какие блоки показать, и держит результаты, чтобы не пересчитывать их на каждый кадр.
/// Раздел «Категории» — по всем тратам периода, журнал и остальные блоки — по выбранной категории.
/// Срезы для списка трат (`StatsSliceRoute`) — тоже здесь: с фильтром выбранной категории.
@Observable
final class StatisticsModel {
    /// Сколько трат в «Крупнейших тратах» (макет `04-stats`).
    static let topLimit = 3
    /// Свой период до стольких дней — столбики по дням, длиннее — по месяцам.
    static let customDailyLimit = 62
    /// Начало журнала выбранной категории: дни целиком, пока строк меньше этого; остальное — списком.
    static let journalPreviewRows = 6

    private(set) var input: StatisticsInput
    private(set) var categories = CategoryVizData(breakdown: [], catalog: CategoryCatalogSnapshot([]))
    private(set) var summary: StatsSummary
    /// Столбики «По дням» / «По часам» / «По месяцам»; `nil` — блока нет (прошедший день).
    private(set) var series: StatsTimeSeries?
    private(set) var pace: StatsPaceState?
    private(set) var habits: StatsHabitsState?
    private(set) var year: StatsYearState?
    /// «Крупнейшие траты» строками: снимки при пересчёте, а не выборка в `body`.
    private(set) var topRows: [ExpenseRowData] = []
    /// Журнал выбранной категории; `nil` — ничего не выбрано.
    private(set) var journal: StatsJournalState?
    /// Дата последней траты — для «К последней трате»; `nil` — трат нет совсем.
    private(set) var lastExpenseDate: Date?

    let engine: StatisticsEngine
    @ObservationIgnored private var hasComputed = false
    /// Все траты базы снимками. Читаются при появлении экрана и после сохранений, а не в `body`:
    /// перевод 20 тыс. моделей в `ExpenseRecord` и выборка — сотни миллисекунд.
    @ObservationIgnored private var storedRecords: [ExpenseRecord] = []
    /// База менялась после последнего чтения.
    @ObservationIgnored private var isStale = true
    @ObservationIgnored private var isVisible = false
    /// Контекст экрана — для строк «Крупнейших трат»; задаётся при появлении.
    @ObservationIgnored private var context: ModelContext?

    init(calendar: Calendar = .autoupdatingCurrent, now: Date = .now) {
        engine = StatisticsEngine(calendar: calendar)
        let period = StatsPeriod.current(.month, now: now, calendar: calendar)
        input = StatisticsInput(period: period, now: now)
        summary = engine.summary(for: period, records: [], now: now)
    }

    // MARK: - Состояние

    var period: StatsPeriod { input.period }
    var now: Date { input.now }
    var calendar: Calendar { engine.calendar }

    var hasExpenses: Bool { lastExpenseDate != nil }
    var isPeriodEmpty: Bool { categories.isEmpty }

    /// Выбор, который есть в данных периода; по нему отфильтрованы сводка и блоки под «Категориями».
    var selection: StatsCategorySelection? { categories.resolved(input.selection) }

    var filter: StatsCategoryFilter { selection?.filter ?? .all }

    /// Имя выбранного для пометки «только Продукты»: категория, подкатегория, «без подкатегории».
    var filterName: String? {
        if let part = categories.part(for: input.selection) { return VizText.name(part) }
        return categories.group(for: input.selection).map(VizText.name)
    }

    /// Тоны ауры: крупнейшие категории периода (без фильтра).
    var auraTones: [GouacheTone] { Array(categories.groups.compactMap(\.tone).prefix(3)) }

    // MARK: - Траты из базы

    /// Экран появился: перечитать траты, если база менялась, пока его не было видно.
    func appear(in context: ModelContext) {
        self.context = context
        isVisible = true
        reloadIfStale(from: context)
    }

    func disappear() {
        isVisible = false
    }

    /// База сохранена (`ModelContext.didSave`): на виду — перечитать сразу, иначе — при следующем появлении.
    func dataDidChange(in context: ModelContext) {
        self.context = context
        isStale = true
        if isVisible { reloadIfStale(from: context) }
    }

    private func reloadIfStale(from context: ModelContext) {
        guard isStale else { return }
        isStale = false
        // Как лента — от новых к старым: журнал выбранной категории берёт порядок трат внутри дня отсюда.
        let descriptor = FetchDescriptor<Expense>(sortBy: [
            SortDescriptor(\.date, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)
        ])
        let expenses = (try? context.fetch(descriptor)) ?? []
        storedRecords = expenses.map(ExpenseRecord.init)
        // До первого `update(_:)` период ещё не задан — посчитает он.
        if hasComputed { recompute() }
    }

    // MARK: - Расчёт

    func update(_ input: StatisticsInput) {
        guard !hasComputed || input != self.input else { return }
        self.input = input
        recompute()
    }

    private func recompute() {
        hasComputed = true
        let records = input.hiddenIDs.isEmpty ? storedRecords : storedRecords.filter { !input.hiddenIDs.contains($0.id) }
        let period = input.period
        let now = input.now

        lastExpenseDate = records.map(\.date).max()
        categories = CategoryVizData(
            breakdown: engine.groupBreakdown(for: period, records: records, stepRank: input.catalog.stepRank),
            catalog: input.catalog
        )
        let filter = self.filter

        summary = engine.summary(for: period, records: records, now: now, filter: filter)
        series = seriesStep(for: period, now: now).map {
            engine.timeSeries(for: period, records: records, step: $0, filter: filter)
        }
        pace = paceState(period: period, records: records, now: now, filter: filter)
        let scale = engine.heatScale(forYearContaining: Self.lastDay(of: period, calendar: calendar), records: records, filter: filter)
        habits = engine.showsHabits(for: period)
            ? StatsHabitsState(
                habits: engine.habits(for: period, records: records, now: now, filter: filter),
                scale: scale,
                hasEnoughData: engine.hasEnoughDataForHabits(for: period, records: records, now: now, filter: filter)
            )
            : nil
        year = yearState(period: period, records: records, filter: filter, scale: scale)
        topRows = makeTopRows(engine.topExpenses(for: period, records: records, limit: Self.topLimit, filter: filter).map(\.id))
        journal = selection.map { journalState(engine.slice(period: period, filter: $0.filter), records: records) }
    }

    // MARK: - Срезы для списка трат

    /// Журнал выбранной категории целиком.
    func journalRoute() -> StatsSliceRoute {
        route(engine.slice(period: period, filter: filter))
    }

    /// Столбик «По дням» / «По часам» / «По месяцам» или клетка карты года.
    func route(bucket: StatsTimeBucket, step: StatsTimeStep) -> StatsSliceRoute {
        route(engine.slice(bucket: bucket, step: step, filter: filter))
    }

    /// День «Темпа».
    func route(dayContaining date: Date) -> StatsSliceRoute {
        route(engine.slice(dayContaining: date, filter: filter))
    }

    /// День недели «Привычек».
    func route(weekday: Int) -> StatsSliceRoute {
        route(engine.slice(weekday: weekday, period: period, now: now, filter: filter))
    }

    private func route(_ slice: StatsExpenseSlice) -> StatsSliceRoute {
        StatsSliceRoute(slice: slice, period: period)
    }

    // MARK: - Внутреннее

    /// Строки топа: модели — одной выборкой по id (их не больше `topLimit`), подпись — дата языка интерфейса.
    private func makeTopRows(_ ids: [UUID]) -> [ExpenseRowData] {
        let expenses = fetchExpenses(ids)
        let dates = AppLanguage.current.dateFormatter(calendar: calendar, now: input.now)
        return ids.compactMap { expenses[$0].map { ExpenseRowData(top: $0, dates: dates) } }
    }

    /// Журнал: начало ленты по дням (`journalPreviewRows`), строки — как в ленте; модели — только этих трат.
    private func journalState(_ slice: StatsExpenseSlice, records: [ExpenseRecord]) -> StatsJournalState {
        let days = engine.expenseDays(in: slice, records: records)
        let preview = StatsExpenseDay.preview(days, rowLimit: Self.journalPreviewRows)
        let expenses = fetchExpenses(preview.flatMap(\.expenseIDs))
        return StatsJournalState(
            days: preview.map { day in
                HomeFeedDay(
                    day: day.day,
                    totalMinor: day.totalMinor,
                    rows: day.expenseIDs.compactMap { expenses[$0].map(ExpenseRowData.init) }
                )
            },
            count: days.reduce(0) { $0 + $1.expenseIDs.count }
        )
    }

    /// Модели трат по id одной выборкой.
    private func fetchExpenses(_ ids: [UUID]) -> [UUID: Expense] {
        guard !ids.isEmpty, let context else { return [:] }
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        return Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Шаг столбиков: день — по часам (только сегодня, §8 п. 15), неделя и месяц — по дням, год — по месяцам,
    /// свой период — по дням, если он не длиннее `customDailyLimit`.
    private func seriesStep(for period: StatsPeriod, now: Date) -> StatsTimeStep? {
        switch period.kind {
        case .day:
            return engine.showsHourly(for: period, now: now) ? .hour : nil
        case .week, .month:
            return .day
        case .year:
            return .month
        case nil:
            let days = PeriodSelection.dayCount(of: period.interval, calendar: calendar)
            return days <= Self.customDailyLimit ? .day : .month
        }
    }

    private func paceState(
        period: StatsPeriod,
        records: [ExpenseRecord],
        now: Date,
        filter: StatsCategoryFilter
    ) -> StatsPaceState? {
        guard engine.showsPace(for: period) else { return nil }
        return StatsPaceState(
            comparison: engine.cumulativeComparison(for: period, records: records, now: now, filter: filter),
            forecast: engine.forecast(for: period, records: records, now: now, filter: filter),
            totalMinor: summary.totalMinor,
            dayCount: PeriodSelection.dayCount(of: period.interval, calendar: calendar),
            hasEnoughData: engine.hasEnoughDataForPace(for: period, records: records, now: now, filter: filter)
        )
    }

    /// Тепловая карта — у всех периодов, кроме «Дня»: год последнего дня периода.
    private func yearState(
        period: StatsPeriod,
        records: [ExpenseRecord],
        filter: StatsCategoryFilter,
        scale: StatsHeatScale?
    ) -> StatsYearState? {
        guard period.kind != .day, let scale else { return nil }
        let lastDay = Self.lastDay(of: period, calendar: calendar)
        return StatsYearState(
            year: calendar.component(.year, from: lastDay),
            months: engine.yearDays(forYearContaining: lastDay, records: records, filter: filter),
            scale: scale
        )
    }

    /// Начало последнего дня периода (конец полуоткрытый).
    static func lastDay(of period: StatsPeriod, calendar: Calendar) -> Date {
        let endDay = calendar.startOfDay(for: period.interval.end)
        guard endDay == period.interval.end else { return endDay }
        return calendar.date(byAdding: .day, value: -1, to: endDay) ?? endDay
    }
}
