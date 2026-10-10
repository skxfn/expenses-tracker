#if DEBUG
import SwiftUI
import ExpenseCore

/// Аргументы запуска статистики для скриншотов без касаний (вместе с `-demoData YES -debugTab statistics`):
/// - `-statsPeriod day|yesterday|week|year|range|past|pastYear` — период (`range` — 3 дня до вчера, как `05-stats-range`);
/// - `-statsExpand YES|<имя>` — раскрыть самую крупную раскрываемую категорию или категорию по имени;
/// - `-statsScroll categories|days|pace|habits|year|top` — прокрутить к блоку;
/// - `-statsFocus <имя>` — как тап по плитке на главной: `AppRouter.openStatistics` с прошлым месяцем и категорией;
/// - вид категорий — ключ настроек напрямую: `-statsCategoryView tiles|strips|sun|ring`.
enum StatsDebugOptions {
    static func applyPeriod(to selection: PeriodSelection, defaults: UserDefaults = .standard) {
        guard let value = defaults.string(forKey: "statsPeriod") else { return }
        let calendar = selection.calendar
        let today = selection.today
        switch value {
        case "day": selection.select(.day)
        case "yesterday":
            selection.select(.day)
            selection.showPrevious()
        case "week": selection.select(.week)
        case "year": selection.select(.year)
        case "pastYear":
            selection.select(.year)
            selection.showPrevious()
        case "past": selection.showPrevious()
        case "range":
            let first = calendar.date(byAdding: .day, value: -3, to: today) ?? today
            let last = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            selection.applyCustom(from: first, through: last)
        default: break
        }
    }

    /// Какую категорию раскрыть после загрузки данных; `nil` — не раскрывать.
    static func expansion(in data: CategoryVizData, defaults: UserDefaults = .standard) -> UUID? {
        guard let value = defaults.string(forKey: "statsExpand") else { return nil }
        let expandable = data.groups.filter(\.isExpandable)
        let named = expandable.first { $0.name == value }
        return (named ?? (defaults.bool(forKey: "statsExpand") ? expandable.first : nil))?.id
    }

    /// Категория верхнего уровня по имени для `-statsFocus`; `nil` — аргумента нет или такой категории нет.
    static func focusGroup(in catalog: CategoryCatalogSnapshot, defaults: UserDefaults = .standard) -> UUID? {
        guard let name = defaults.string(forKey: "statsFocus") else { return nil }
        return catalog.entries.values.first { $0.parentID == nil && $0.name == name }?.id
    }

    static func scroll(_ proxy: ScrollViewProxy, defaults: UserDefaults = .standard) async {
        guard let anchor = defaults.string(forKey: "statsScroll").flatMap(StatsAnchor.init(rawValue:)) else { return }
        try? await Task.sleep(for: .seconds(1.5))
        proxy.scrollTo(anchor, anchor: .top)
    }
}
#endif
