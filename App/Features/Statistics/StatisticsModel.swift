import Foundation
import Observation
import ExpenseCore

/// Входные данные статистики: снимки трат и каталога (без SwiftData), период и раскрытая категория.
struct StatisticsInput: Equatable {
    var records: [ExpenseRecord] = []
    var catalog = CategoryCatalogSnapshot([])
    var period: StatsPeriod
    var now: Date
    /// Раскрытая категория раздела «Категории»: фильтрует все остальные блоки (`.group`).
    var expandedID: UUID?
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

/// Расчёты вкладки «Статистика» (INTEGRATION §4.6–4.8). Все суммы считает `StatisticsEngine`; модель
/// выбирает, какие блоки показать, и держит результаты, чтобы не пересчитывать их на каждый кадр.
/// Раздел «Категории» — по всем тратам периода, остальные блоки — по раскрытой категории.
@Observable
final class StatisticsModel {
    /// Сколько трат в «Крупнейших тратах» (макет `04-stats`).
    static let topLimit = 3
    /// Свой период до стольких дней — столбики по дням, длиннее — по месяцам.
    static let customDailyLimit = 62

    private(set) var input: StatisticsInput
    private(set) var categories = CategoryVizData(breakdown: [], catalog: CategoryCatalogSnapshot([]))
    private(set) var summary: StatsSummary
    /// Столбики «По дням» / «По часам» / «По месяцам»; `nil` — блока нет (прошедший день).
    private(set) var series: StatsTimeSeries?
    private(set) var pace: StatsPaceState?
    private(set) var habits: StatsHabitsState?
    private(set) var year: StatsYearState?
    private(set) var topIDs: [UUID] = []
    /// Дата последней траты — для «К последней трате»; `nil` — трат нет совсем.
    private(set) var lastExpenseDate: Date?

    let engine: StatisticsEngine
    @ObservationIgnored private var hasComputed = false

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

    /// Раскрытая категория, по которой отфильтрованы блоки под разделом «Категории».
    var filterGroup: CategoryVizGroup? { categories.expandedGroup(input.expandedID) }

    /// Тоны ауры: крупнейшие категории периода (без фильтра).
    var auraTones: [GouacheTone] { Array(categories.groups.compactMap(\.tone).prefix(3)) }

    // MARK: - Расчёт

    func update(_ input: StatisticsInput) {
        guard !hasComputed || input != self.input else { return }
        hasComputed = true
        self.input = input
        let records = input.records
        let period = input.period
        let now = input.now

        lastExpenseDate = records.map(\.date).max()
        categories = CategoryVizData(
            breakdown: engine.groupBreakdown(for: period, records: records, stepRank: input.catalog.stepRank),
            catalog: input.catalog
        )
        let filter: StatsCategoryFilter = filterGroup?.id.map { .group($0) } ?? .all

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
        topIDs = engine.topExpenses(for: period, records: records, limit: Self.topLimit, filter: filter).map(\.id)
    }

    // MARK: - Внутреннее

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
