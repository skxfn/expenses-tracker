import Foundation
import Observation
import SwiftData
import ExpenseCore

/// Данные главной: траты только показанного периода и отрезка сравнения «к той же дате» (D5,
/// `StatisticsEngine.comparisonInterval`), а не вся база, и всё, что из них считается (`HomeContent`).
///
/// Выборка — при смене периода или «сейчас» и после сохранения базы (`dataDidChange`), а не в `body`: перевод
/// моделей в `ExpenseRecord` при каждом пересчёте экрана (свайп, тост, подсветка) на большой базе занимает сотни
/// миллисекунд (AGENTS.md). Скрытые `PendingDeletion` отфильтровываются в памяти из снимков последней выборки.
/// `@Query` + `onChange` здесь не подходит: после правки суммы или категории массив состоит из тех же
/// объектов, сравнение не видит перемены, и пересчёт бы её пропустил.
@Observable
final class HomeModel {
    /// Всё, кроме самих данных, от чего зависит главная.
    struct Inputs: Equatable {
        let period: StatsPeriod
        let now: Date
        let calendar: Calendar
        let hiddenIDs: Set<UUID>

        /// Другая выборка нужна только при смене этих полей; скрытые фильтруются без неё.
        fileprivate func needsFetch(comparedTo other: Inputs) -> Bool {
            period != other.period || now != other.now || calendar != other.calendar
        }
    }

    /// Снимки последней выборки — значения, не модели SwiftData: модель после удаления или `rollback()` читать нельзя.
    private struct Snapshot {
        let inputs: Inputs
        let records: [ExpenseRecord]
        /// Строки трат показанного периода, от новых к старым.
        let rows: [ExpenseRowData]
        /// Последние траты всей базы, от новых к старым, — для «К последней трате» и первого запуска.
        let recent: [ExpenseRecord]
        /// В базе трат не больше, чем в `recent`.
        let recentIsAll: Bool
        let catalog: CategoryCatalogSnapshot
    }

    /// Сколько последних трат держать сверх скрытых: скрытие ещё одной обходится без выборки.
    private static let recentReserve = 2

    /// До первой выборки — пусто; первая — при появлении экрана (`onChange(of:initial:)`).
    private(set) var content: HomeContent
    @ObservationIgnored private var snapshot: Snapshot?

    init(period: StatsPeriod, now: Date, calendar: Calendar) {
        content = HomeContent(
            records: [], rows: [], latest: nil, catalog: CategoryCatalogSnapshot([]),
            period: period, now: now, calendar: calendar
        )
    }

    /// Вход изменился: новая выборка только при смене периода или «сейчас», скрытые — из снимков.
    func update(_ inputs: Inputs, context: ModelContext) {
        if let snapshot, !inputs.needsFetch(comparedTo: snapshot.inputs) {
            rebuild(inputs, from: snapshot, context: context)
        } else {
            reload(inputs, context: context)
        }
    }

    /// База сохранена: заново выбрать траты и пересчитать главную.
    func dataDidChange(_ inputs: Inputs, context: ModelContext) {
        reload(inputs, context: context)
    }

    /// Ошибка чтения даёт пустую ленту, как раньше у `@Query`.
    private func reload(_ inputs: Inputs, context: ModelContext) {
        let store = ExpenseStore(context: context)
        let period = inputs.period
        let comparison = StatisticsEngine(calendar: inputs.calendar).comparisonInterval(for: period, now: inputs.now)
        let interval = DateInterval(
            start: min(comparison.start, period.interval.start),
            end: max(comparison.end, period.interval.end)
        )
        let expenses = (try? store.expenses(in: interval)) ?? []
        let recentLimit = inputs.hiddenIDs.count + Self.recentReserve
        let recent = (try? store.recentExpenses(limit: recentLimit)) ?? []
        let snapshot = Snapshot(
            inputs: inputs,
            records: expenses.map(ExpenseRecord.init),
            rows: expenses.filter { period.contains($0.date) }.map(ExpenseRowData.init),
            recent: recent.map(ExpenseRecord.init),
            recentIsAll: recent.count < recentLimit,
            catalog: CategoryCatalogSnapshot(categories: (try? store.allCategories()) ?? [])
        )
        self.snapshot = snapshot
        rebuild(inputs, from: snapshot, context: context)
    }

    private func rebuild(_ inputs: Inputs, from snapshot: Snapshot, context: ModelContext) {
        let hidden = inputs.hiddenIDs
        let latest = snapshot.recent.first { !hidden.contains($0.id) }?.date
        // Скрыты все запомненные последние траты, а в базе есть и другие — выбрать заново.
        if latest == nil, !snapshot.recentIsAll {
            return reload(inputs, context: context)
        }
        content = HomeContent(
            records: hidden.isEmpty ? snapshot.records : snapshot.records.filter { !hidden.contains($0.id) },
            rows: hidden.isEmpty ? snapshot.rows : snapshot.rows.filter { !hidden.contains($0.id) },
            latest: latest,
            catalog: snapshot.catalog,
            period: inputs.period,
            now: inputs.now,
            calendar: inputs.calendar
        )
    }
}
