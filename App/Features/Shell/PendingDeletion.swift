import Foundation
import Observation
import SwiftData
import ExpenseCore

/// Удаление траты с отменой (INTEGRATION §4.9): строка сразу скрывается, хранилище
/// не трогается 4 с. Удаление выполняется по таймеру, при уходе в фон
/// (`commitNow()`) или при следующем удалении. «Отменить» просто снимает пометку.
@Observable
final class PendingDeletion {
    /// Снимок для тоста: свойства удалённой модели потом читать нельзя (ловушка AGENTS.md).
    struct Item: Identifiable, Equatable {
        let id: UUID
        /// Подпись тоста, собранная экраном заранее.
        let title: String
    }

    static let delay: Duration = .seconds(4)

    private(set) var item: Item?
    /// Последняя ошибка удаления — экран показывает её алертом.
    var errorMessage: String?

    private var store: ExpenseStore?
    private var timer: Task<Void, Never>?

    /// id, которые лента и календарь должны скрыть.
    var hiddenIDs: Set<UUID> { item.map { [$0.id] } ?? [] }

    /// Пометить трату на удаление. Предыдущая пометка удаляется сразу.
    func schedule(_ item: Item, store: ExpenseStore) {
        commitNow()
        self.item = item
        self.store = store
        startTimer()
    }

    /// «Отменить»: строка возвращается, хранилище не менялось.
    func undo() {
        timer?.cancel()
        timer = nil
        item = nil
        store = nil
    }

    /// Палец на тосте — таймер стоит.
    func pause() {
        timer?.cancel()
        timer = nil
    }

    /// Палец убран — отсчёт заново.
    func resume() {
        guard item != nil, timer == nil else { return }
        startTimer()
    }

    /// Удалить сейчас (уход в фон, следующее удаление).
    func commitNow() {
        timer?.cancel()
        timer = nil
        guard let item, let store else { return }
        self.item = nil
        self.store = nil
        do {
            if let expense = try store.expense(id: item.id) {
                try store.deleteExpense(expense)
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func startTimer() {
        timer = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.commitNow()
        }
    }
}
