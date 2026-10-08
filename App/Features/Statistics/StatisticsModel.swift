import Foundation
import Observation
import ExpenseCore

/// Исходные данные статистики: снимки расходов и оформление категорий без SwiftData.
struct StatisticsSource: Equatable {
    var records: [ExpenseRecord] = []
    var notes: [UUID: String] = [:]
    var categories: [UUID: CategoryAppearance] = [:]

    init() {}

    init(expenses: [Expense], categories: [ExpenseCategory]) {
        records = expenses.map { ExpenseRecord($0) }
        notes = Dictionary(
            expenses.lazy.filter { !$0.note.isEmpty }.map { ($0.id, $0.note) },
            uniquingKeysWith: { first, _ in first }
        )
        self.categories = Dictionary(
            categories.map { ($0.id, CategoryAppearance($0)) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

/// Строка разбивки по категориям.
struct CategoryShareRow: Identifiable {
    let filter: StatsCategoryFilter
    let appearance: CategoryAppearance
    let totalMinor: Int64
    let share: Double
    let isSelected: Bool

    var id: StatsCategoryFilter { filter }
}

/// Строка топа трат.
struct TopExpenseRow: Identifiable {
    let id: UUID
    let appearance: CategoryAppearance
    let note: String
    let date: Date
    let amountMinor: Int64
}

/// Средняя трата в один из дней недели.
struct WeekdayRow: Identifiable {
    /// Нумерация `Calendar`: 1 — воскресенье.
    let id: Int
    /// «пн»
    let label: String
    let averageMinor: Int64
}

/// Состояние и расчёты вкладки «Статистика». Все суммы считает `StatisticsEngine`,
/// модель только выбирает период и фильтр и готовит строки для показа.
@Observable
final class StatisticsModel {
    private(set) var kind: StatsPeriodKind
    private(set) var period: StatsPeriod
    private(set) var filter: StatsCategoryFilter = .all
    private(set) var now: Date

    private(set) var summary: StatsSummary
    private(set) var categoryRows: [CategoryShareRow] = []
    private(set) var timeSeries: StatsTimeSeries
    private(set) var cumulative: StatsCumulativeComparison?
    private(set) var weekdays: [WeekdayRow] = []
    private(set) var topExpenses: [TopExpenseRow] = []

    private var source = StatisticsSource()
    private let engine: StatisticsEngine

    static let topLimit = 5

    init(kind: StatsPeriodKind = .month, calendar: Calendar = .autoupdatingCurrent, now: Date = .now) {
        let engine = StatisticsEngine(calendar: calendar)
        let period = StatsPeriod.current(kind, now: now, calendar: calendar)
        self.engine = engine
        self.kind = kind
        self.period = period
        self.now = now
        summary = engine.summary(for: period, records: [], now: now)
        timeSeries = engine.timeSeries(for: period, records: [])
    }

    // MARK: - Состояние для показа

    var hasExpenses: Bool { !source.records.isEmpty }

    /// В периоде нет ни одной траты (без учёта фильтра).
    var isPeriodEmpty: Bool { categoryRows.isEmpty }

    /// Итог периода по всем категориям — для центра диаграммы.
    var periodTotalMinor: Int64 { categoryRows.reduce(0) { $0 + $1.totalMinor } }

    var title: String { period.title(now: now, calendar: engine.calendar) }

    /// Вперёд можно листать только до периода, в который попадает сегодняшний день.
    var canShowNext: Bool { period.interval.end <= now }

    var isCurrentPeriod: Bool { period.contains(now) }

    var showsCumulative: Bool { kind != .day }

    /// Для дня и недели средние по дням недели повторяют столбцы по времени.
    var showsWeekdays: Bool { kind == .month || kind == .year }

    /// Название категории, по которой отфильтрована статистика.
    var filterTitle: String? {
        filter == .all ? nil : appearance(for: filter).name
    }

    /// «к прошлому месяцу».
    var comparisonSuffix: String {
        switch kind {
        case .day: "к предыдущему дню"
        case .week: "к прошлой неделе"
        case .month: "к прошлому месяцу"
        case .year: "к прошлому году"
        }
    }

    /// Подписи линий накопительного графика — заголовки периодов, а не «этот/прошлый»:
    /// при листании назад «этот месяц» был бы неправдой.
    var currentSeriesLabel: String { title }

    var previousSeriesLabel: String {
        period.previous(in: engine.calendar).title(now: now, calendar: engine.calendar)
    }

    // MARK: - Действия

    func update(source: StatisticsSource, now: Date = .now) {
        self.source = source
        self.now = now
        recompute()
    }

    /// Смена вида периода. Если смотрели прошлый период — остаёмся рядом с ним, а не прыгаем в сегодня.
    func select(_ kind: StatsPeriodKind) {
        guard kind != self.kind else { return }
        let anchor = period.contains(now) ? now : period.interval.start
        self.kind = kind
        period = .current(kind, now: anchor, calendar: engine.calendar)
        recompute()
    }

    func showPrevious() {
        period = period.previous(in: engine.calendar)
        recompute()
    }

    func showNext() {
        guard canShowNext else { return }
        period = period.next(in: engine.calendar)
        recompute()
    }

    func showCurrent() {
        period = .current(kind, now: now, calendar: engine.calendar)
        recompute()
    }

    /// Тап по категории включает фильтр, повторный — снимает.
    func toggleFilter(_ filter: StatsCategoryFilter) {
        self.filter = self.filter == filter ? .all : filter
        recompute()
    }

    func clearFilter() {
        filter = .all
        recompute()
    }

    // MARK: - Расчёт

    private func recompute() {
        let records = source.records
        summary = engine.summary(for: period, records: records, now: now, filter: filter)
        categoryRows = engine.categoryBreakdown(for: period, records: records).map { share in
            let rowFilter: StatsCategoryFilter = share.categoryID.map { .category($0) } ?? .uncategorized
            return CategoryShareRow(
                filter: rowFilter,
                appearance: appearance(for: rowFilter),
                totalMinor: share.totalMinor,
                share: share.share,
                isSelected: rowFilter == filter
            )
        }
        timeSeries = engine.timeSeries(for: period, records: records, filter: filter)
        cumulative = showsCumulative
            ? engine.cumulativeComparison(for: period, records: records, now: now, filter: filter)
            : nil
        let weekdaySymbols = engine.calendar.shortStandaloneWeekdaySymbols
        weekdays = showsWeekdays
            ? engine.weekdayAverages(for: period, records: records, now: now, filter: filter).map { average in
                WeekdayRow(id: average.weekday, label: weekdaySymbols[average.weekday - 1], averageMinor: average.averageMinor)
            }
            : []
        topExpenses = engine.topExpenses(for: period, records: records, limit: Self.topLimit, filter: filter).map { record in
            TopExpenseRow(
                id: record.id,
                appearance: appearance(for: record.categoryID.map { .category($0) } ?? .uncategorized),
                note: source.notes[record.id] ?? "",
                date: record.date,
                amountMinor: record.amountMinor
            )
        }
    }

    private func appearance(for filter: StatsCategoryFilter) -> CategoryAppearance {
        switch filter {
        case .all, .uncategorized:
            .uncategorized
        case .category(let id):
            source.categories[id] ?? .uncategorized
        }
    }
}

extension StatsPeriodKind {
    var title: String {
        switch self {
        case .day: "День"
        case .week: "Неделя"
        case .month: "Месяц"
        case .year: "Год"
        }
    }
}
