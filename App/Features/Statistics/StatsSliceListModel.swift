import Foundation
import Observation
import SwiftData
import ExpenseCore

/// Пуш «траты среза» (`AppRoute.statisticsExpenses`): срез и период статистики, из которого он открыт.
struct StatsSliceRoute: Hashable {
    let slice: StatsExpenseSlice
    /// Период статистики — подпись журнала категории и дня недели («октябрь»).
    let period: StatsPeriod
}

/// Траты среза по дням для `StatsSliceListView`. Выборка — при появлении и после сохранения базы (`onDataSaved`),
/// а не в `body`; траты, помеченные на удаление (`PendingDeletion`), отфильтровываются из снимков без выборки.
@Observable
final class StatsSliceListModel {
    let route: StatsSliceRoute
    let engine: StatisticsEngine

    /// Дни от новых к старым, строки — снимки `ExpenseRowData`.
    private(set) var days: [HomeFeedDay] = []
    private(set) var totalMinor: Int64 = 0
    private(set) var count = 0
    /// Имя категории среза: «Кафе», «Супермаркет», «Продукты · без подкатегории», «Без категории»; `nil` — все траты.
    private(set) var filterName: String?
    /// Тон категории среза — для ауры; `nil` — все траты или «Без категории».
    private(set) var tone: GouacheTone?
    /// Первая выборка сделана: до неё пустой список — не «Трат нет».
    private(set) var isLoaded = false

    /// Снимки последней выборки: значения, не модели SwiftData (удалённую модель читать нельзя).
    @ObservationIgnored private var records: [ExpenseRecord] = []
    @ObservationIgnored private var rows: [UUID: ExpenseRowData] = [:]
    @ObservationIgnored private var hiddenIDs: Set<UUID> = []

    init(route: StatsSliceRoute, calendar: Calendar = .autoupdatingCurrent) {
        self.route = route
        engine = StatisticsEngine(calendar: calendar)
    }

    var calendar: Calendar { engine.calendar }

    /// Заново выбрать траты среза (появление экрана, сохранение базы). Ошибка чтения — пустой список.
    func reload(context: ModelContext, hiddenIDs: Set<UUID>) {
        let store = ExpenseStore(context: context)
        let slice = route.slice
        var records: [ExpenseRecord] = []
        var rows: [UUID: ExpenseRowData] = [:]
        // `expenses(in:)` — от новых к старым, как лента: порядок трат внутри дня тот же.
        for expense in (try? store.expenses(in: slice.interval)) ?? [] {
            let record = ExpenseRecord(expense)
            guard slice.contains(record, calendar: calendar) else { continue }
            records.append(record)
            rows[record.id] = ExpenseRowData(expense)
        }
        self.records = records
        self.rows = rows
        let catalog = CategoryCatalogSnapshot(categories: (try? store.allCategories()) ?? [])
        (filterName, tone) = Self.describe(slice.filter, catalog: catalog)
        isLoaded = true
        update(hiddenIDs: hiddenIDs)
    }

    /// Пометки удаления сменились: пересобрать дни из снимков.
    func update(hiddenIDs: Set<UUID>) {
        self.hiddenIDs = hiddenIDs
        let visible = hiddenIDs.isEmpty ? records : records.filter { !hiddenIDs.contains($0.id) }
        days = engine.expenseDays(in: route.slice, records: visible).map { day in
            HomeFeedDay(day: day.day, totalMinor: day.totalMinor, rows: day.expenseIDs.compactMap { rows[$0] })
        }
        totalMinor = visible.reduce(0) { $0 + $1.amountMinor }
        count = visible.count
    }

    /// Имя и тон категории фильтра по каталогу. Трата прямо в категорию с подкатегориями — «без подкатегории».
    private static func describe(_ filter: StatsCategoryFilter, catalog: CategoryCatalogSnapshot) -> (String?, GouacheTone?) {
        switch filter {
        case .all:
            return (nil, nil)
        case .uncategorized:
            return (String(localized: "stats.legacy.uncategorized"), nil)
        case .group(let id):
            return (catalog[id]?.name, catalog[id]?.tone)
        case .category(let id):
            guard let entry = catalog[id] else { return (nil, nil) }
            guard entry.parentID == nil, entry.subcategoryCount > 0 else { return (entry.name, entry.tone) }
            return (entry.name + " · " + String(localized: "viz.noSubLegend"), entry.tone)
        }
    }
}
