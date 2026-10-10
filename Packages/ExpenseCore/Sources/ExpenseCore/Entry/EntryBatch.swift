import Foundation

/// Траты, записанные через «Ещё одна», пока шит записи открыт: пилюля «2 траты · 21,50»
/// и шит «Только что записанные» (§4.9). Живёт в модели формы до закрытия шита.
public struct EntryBatch: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let amountMinor: Int64
    }

    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    /// Сумма пакета; при переполнении — `Int64.max` (до него не дойти: сумма поля ограничена `AmountInput.maxMinor`).
    public var totalMinor: Int64 {
        entries.reduce(0) { total, entry in
            let (sum, overflow) = total.addingReportingOverflow(entry.amountMinor)
            return overflow ? .max : sum
        }
    }

    public mutating func append(id: UUID, amountMinor: Int64) {
        entries.append(Entry(id: id, amountMinor: amountMinor))
    }

    /// Без трат с этими `id` (удалённые или скрытые до отмены удаления).
    public func excluding(_ ids: Set<UUID>) -> EntryBatch {
        EntryBatch(entries: entries.filter { !ids.contains($0.id) })
    }

    /// Оставить только траты, которые ещё есть в хранилище.
    public mutating func keep(where exists: (UUID) -> Bool) {
        entries.removeAll { !exists($0.id) }
    }
}

/// Ряд образцов в шите записи: частые категории и «Все» (§4.9).
public enum SwatchRow {
    /// Частых образцов в ряду (шестой может занять выбранная во «Всех категориях»).
    public static let frequentCount = 6

    /// Категория, выбранная во «Всех категориях» (или категория траты при правке), которой нет среди частых,
    /// замещает последний образец. Порядок остальных не меняется.
    public static func compose<Item: Identifiable>(frequent: [Item], pinned: Item?, limit: Int = frequentCount) -> [Item] {
        let head = Array(frequent.prefix(limit))
        guard let pinned, limit > 0, !head.contains(where: { $0.id == pinned.id }) else { return head }
        return Array(head.prefix(limit - 1)) + [pinned]
    }
}
