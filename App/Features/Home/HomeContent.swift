import Foundation
import ExpenseCore

/// День ленты: строки от новых к старым и сумма дня.
struct HomeFeedDay: Identifiable {
    /// Начало дня.
    let day: Date
    let totalMinor: Int64
    let rows: [ExpenseRowData]

    var id: Date { day }
}

/// Данные главной за выбранный период: итог со сравнением «к той же дате» (D5), обзор категорий,
/// лента по дням и тона ауры. Строится в `HomeModel` из выборки периода и отрезка сравнения (траты — уже
/// без скрытых `PendingDeletion`), дальше только значения: расчёты — `StatisticsEngine`, строки — снимки `ExpenseRowData`.
struct HomeContent {
    enum State {
        /// Трат нет совсем (`home.empty.firstRun`): ни итога, ни обзора, ни ауры.
        case firstRun
        /// В периоде трат нет, но они есть в другом (`home.empty.period.*` + «К последней трате»).
        case emptyPeriod(latest: Date)
        case filled
    }

    /// Период, за который посчитано, — ключ ленты: другой период — новый список.
    let period: StatsPeriod
    let summary: StatsSummary
    let overview: CategoryVizData
    let days: [HomeFeedDay]
    /// Тона крупнейших категорий периода по убыванию суммы — пятна ауры.
    let auraTones: [GouacheTone]
    let state: State

    /// - Parameters:
    ///   - records: траты периода и отрезка сравнения (`StatisticsEngine.comparisonInterval`), без скрытых.
    ///   - rows: строки трат периода от новых к старым, без скрытых.
    ///   - latest: дата последней траты всей базы (без скрытых); `nil` — трат нет совсем.
    init(
        records: [ExpenseRecord],
        rows: [ExpenseRowData],
        latest: Date?,
        catalog: CategoryCatalogSnapshot,
        period: StatsPeriod,
        now: Date,
        calendar: Calendar
    ) {
        self.period = period
        let engine = StatisticsEngine(calendar: calendar)
        let breakdown = engine.groupBreakdown(for: period, records: records, stepRank: catalog.stepRank)

        summary = engine.summary(for: period, records: records, now: now)
        overview = CategoryVizData(breakdown: breakdown, catalog: catalog)
        auraTones = Array(overview.groups.compactMap(\.tone).prefix(AuraBackground.defaultLayout.count))
        days = Self.days(rows.filter { period.contains($0.date) }, calendar: calendar)

        if let latest {
            state = days.isEmpty ? .emptyPeriod(latest: latest) : .filled
        } else {
            state = .firstRun
        }
    }

    /// id строк ленты по порядку — ключ анимации вставки и удаления.
    var rowIDs: [UUID] { days.flatMap { $0.rows.map(\.id) } }

    /// Траты подряд по дням; порядок внутри дня — как пришёл (новые выше).
    private static func days(_ expenses: [ExpenseRowData], calendar: Calendar) -> [HomeFeedDay] {
        var days: [HomeFeedDay] = []
        var day: Date?
        var rows: [ExpenseRowData] = []
        var total: Int64 = 0

        func flush() {
            guard let day, !rows.isEmpty else { return }
            days.append(HomeFeedDay(day: day, totalMinor: total, rows: rows))
        }

        for expense in expenses {
            let start = calendar.startOfDay(for: expense.date)
            if start != day {
                flush()
                day = start
                rows = []
                total = 0
            }
            rows.append(expense)
            total += expense.amountMinor
        }
        flush()
        return days
    }
}
