#if DEBUG
import SwiftUI
import ExpenseCore

/// `-debugHome ring,range,empty,scrolled,saved` (через запятую) — состояния главной для скриншотов без касаний:
/// `ring` — обзор «Кольцо» (настройка не меняется); `range` — свой период: 3 дня, кончающиеся вчера
/// (как «5–7 окт» в `03-home-range`); `day`, `week`, `year` — текущий период этого вида, `past` — прошлый месяц;
/// `empty` — прошедший месяц без трат (год назад: демо-данные — 3 месяца);
/// `scrolled` — лента прокручена к третьему дню (виден закреплённый заголовок); `saved` — через 2 с в базу
/// пишется копия последней траты и подсвечивается, как после «Сохранить» (база меняется!).
/// Первый запуск — без `-demoData` на чистой установке.
enum HomeDebug {
    private static let options: Set<String> = Set(
        (UserDefaults.standard.string(forKey: "debugHome") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    )

    static var overviewStyle: HomeOverviewStyle? {
        options.contains("ring") ? .ring : nil
    }

    static func initialPeriod() -> PeriodSelection? {
        if options.contains("range") {
            let selection = PeriodSelection()
            let today = selection.today
            let first = selection.calendar.date(byAdding: .day, value: -3, to: today) ?? today
            let last = selection.calendar.date(byAdding: .day, value: -1, to: today) ?? today
            selection.applyCustom(from: first, through: last)
            return selection
        }
        if options.contains("empty") {
            let selection = PeriodSelection()
            let yearAgo = selection.calendar.date(byAdding: .year, value: -1, to: selection.now) ?? selection.now
            selection.apply(.current(.month, now: yearAgo, calendar: selection.calendar))
            return selection
        }
        if options.contains("past") {
            let selection = PeriodSelection()
            selection.showPrevious()
            return selection
        }
        if let kind = [StatsPeriodKind.day, .week, .year].first(where: { options.contains($0.rawValue) }) {
            return PeriodSelection(kind: kind)
        }
        return nil
    }

    static func scrollIfRequested(_ content: HomeContent, proxy: ScrollViewProxy) async {
        guard options.contains("scrolled"), content.days.count > 2, let target = content.days[2].rows.first?.id else { return }
        try? await Task.sleep(for: .milliseconds(600))
        proxy.scrollTo(target, anchor: .top)
    }

    /// `saved`: через 2 с записать копию последней траты и отдать её id, как «Сохранить» в шите (save-reward).
    static func simulateSaveIfRequested(store: ExpenseStore, router: AppRouter) async {
        guard options.contains("saved") else { return }
        try? await Task.sleep(for: .seconds(2))
        guard let latest = try? store.recentExpenses(limit: 1).first,
              let saved = try? store.addExpense(
                  amountMinor: latest.amountMinor, date: .now, note: latest.note, category: latest.category
              )
        else { return }
        router.savedExpenseID = saved.id
    }
}
#endif
