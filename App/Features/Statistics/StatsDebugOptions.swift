#if DEBUG
import SwiftUI
import ExpenseCore

/// Аргументы запуска статистики для скриншотов без касаний (вместе с `-demoData YES -debugTab statistics`):
/// - `-statsPeriod day|yesterday|week|year|range|past|pastYear` — период (`range` — 3 дня до вчера, как `05-stats-range`);
/// - `-statsExpand YES` — раскрыть самую крупную раскрываемую категорию;
/// - `-statsScroll categories|days|pace|habits|year|top` — прокрутить к блоку;
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

    static var expandsFirst: Bool {
        UserDefaults.standard.bool(forKey: "statsExpand")
    }

    static func scroll(_ proxy: ScrollViewProxy, defaults: UserDefaults = .standard) async {
        guard let anchor = defaults.string(forKey: "statsScroll").flatMap(StatsAnchor.init(rawValue:)) else { return }
        try? await Task.sleep(for: .seconds(1.5))
        proxy.scrollTo(anchor, anchor: .top)
    }
}
#endif
