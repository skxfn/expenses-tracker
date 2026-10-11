import Foundation
import Observation
import SwiftData
import UIKit
import ExpenseCore

/// Удаление траты с отменой (INTEGRATION §4.9): строка сразу скрывается, хранилище
/// не трогается 4 с (с VoiceOver — 10 с). Удаление выполняется по таймеру, при уходе в фон
/// (`commitNow()`) или при следующем удалении. «Отменить» просто снимает пометку.
/// Пока тост держат (палец или фокус VoiceOver), отсчёт стоит; держать могут несколько тостов сразу —
/// под шитом «Только что записанные» виден и тост корня, поэтому удержания считаются.
@Observable
final class PendingDeletion {
    /// Снимок для тоста: свойства удалённой модели потом читать нельзя (ловушка AGENTS.md).
    struct Item: Identifiable, Equatable {
        let id: UUID
        /// Подпись тоста, собранная экраном заранее.
        let title: String
    }

    static let delay: Duration = .seconds(4)
    /// С VoiceOver за 4 с от объявления до «Отменить» не добраться, а удаление необратимо.
    static let voiceOverDelay: Duration = .seconds(10)
    /// Предел удержания: если отпускание потерялось (тост исчез, фокус не вернулся), удаление всё равно состоится.
    static let maxHold: Duration = .seconds(60)

    private(set) var item: Item?
    /// Последняя ошибка удаления — экран показывает её алертом.
    var errorMessage: String?

    private var store: ExpenseStore?
    private var timer: Task<Void, Never>?
    /// Сколько тостов текущей пометки держат таймер.
    private var holdCount = 0

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
        holdCount = 0
        item = nil
        store = nil
    }

    /// Палец или фокус VoiceOver на тосте траты `id` — таймер стоит (не дольше `maxHold`).
    /// Удержание тоста прежней пометки (`id` не текущий) не считается.
    func pause(for id: UUID?) {
        guard let item, item.id == id else { return }
        holdCount += 1
        startTimer(after: Self.maxHold)
    }

    /// Тост траты `id` отпустили (палец убран, фокус ушёл, тост исчез): когда не держит ни один — отсчёт заново.
    func resume(for id: UUID?) {
        guard let item, item.id == id, holdCount > 0 else { return }
        holdCount -= 1
        if holdCount == 0 { startTimer() }
    }

    /// VoiceOver включили или выключили при тосте на экране: отсчёт заново с длительностью для нового состояния.
    func voiceOverChanged(isRunning: Bool) {
        guard item != nil, holdCount == 0 else { return }
        startTimer(after: isRunning ? Self.voiceOverDelay : Self.delay)
    }

    /// Удалить сейчас (уход в фон, следующее удаление).
    func commitNow() {
        timer?.cancel()
        timer = nil
        holdCount = 0
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

    private func startTimer(after delay: Duration? = nil) {
        timer?.cancel()
        let delay = delay ?? (UIAccessibility.isVoiceOverRunning ? Self.voiceOverDelay : Self.delay)
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.commitNow()
        }
    }
}
