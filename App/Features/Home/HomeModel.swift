import Foundation
import Observation
import SwiftData
import ExpenseCore

/// Данные главной: траты только показанного периода и отрезка сравнения «к той же дате» (D5,
/// `StatisticsEngine.comparisonInterval`), а не вся база, и всё, что из них считается (`HomeContent`).
///
/// Пересчёт — при смене входа (`Inputs`: период, «сейчас», скрытые `PendingDeletion`) и после сохранения базы
/// (`ModelContext.didSave`), а не в `body`: перевод моделей в `ExpenseRecord` при каждом пересчёте экрана
/// (свайп, тост, подсветка) на большой базе занимает сотни миллисекунд (AGENTS.md).
/// `@Query` + `onChange` здесь не подходит: после правки суммы или категории массив состоит из тех же
/// объектов, сравнение не видит перемены, и пересчёт бы её пропустил.
@Observable
final class HomeModel {
    /// Всё, кроме самих данных, от чего зависит выборка.
    struct Inputs: Equatable {
        let period: StatsPeriod
        let now: Date
        let calendar: Calendar
        let hiddenIDs: Set<UUID>
    }

    /// До первой выборки — пусто; первая — при появлении экрана (`onChange(of:initial:)`).
    private(set) var content: HomeContent

    init(period: StatsPeriod, now: Date, calendar: Calendar) {
        content = HomeContent(expenses: [], latest: nil, categories: [], period: period, now: now, calendar: calendar)
    }

    /// Заново выбрать траты и пересчитать главную. Ошибка чтения даёт пустую ленту, как раньше у `@Query`.
    func reload(_ inputs: Inputs, context: ModelContext) {
        let store = ExpenseStore(context: context)
        let comparison = StatisticsEngine(calendar: inputs.calendar).comparisonInterval(for: inputs.period, now: inputs.now)
        let interval = DateInterval(
            start: min(comparison.start, inputs.period.interval.start),
            end: max(comparison.end, inputs.period.interval.end)
        )
        let expenses = ((try? store.expenses(in: interval)) ?? []).filter { !inputs.hiddenIDs.contains($0.id) }
        // Последняя трата всей базы — для «К последней трате» и первого запуска; скрытые пропускаем.
        let latest = ((try? store.recentExpenses(limit: inputs.hiddenIDs.count + 1)) ?? [])
            .first { !inputs.hiddenIDs.contains($0.id) }?
            .date
        content = HomeContent(
            expenses: expenses,
            latest: latest,
            categories: (try? store.allCategories()) ?? [],
            period: inputs.period,
            now: inputs.now,
            calendar: inputs.calendar
        )
    }
}
