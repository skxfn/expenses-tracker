import Foundation

/// Границы одной ступени шкалы heat — подпись выделенной ступени в легенде календаря («5 дней · 25–50»).
public enum StatsHeatLevelRange: Sendable, Hashable {
    /// Ступень 0 — дни без трат.
    case zero
    /// Ступень 1 — меньше первой границы («до 25»).
    case below(Int64)
    /// Средняя ступень — от `lower` включительно до `upper`, не включая («25–50»).
    case between(lower: Int64, upper: Int64)
    /// Последняя ступень — от последней границы («75+»).
    case from(Int64)
}

extension StatsHeatScale {
    /// Ступеней в легенде: 0, «до …» и по одной от каждой границы. Без границ — только 0 (как `cal.legend.items`).
    public var levelCount: Int {
        thresholds.isEmpty ? 1 : thresholds.count + 2
    }

    /// Границы ступени `level` (как у `level(forMinor:)`); `nil` — такой ступени в легенде нет.
    public func range(ofLevel level: Int) -> StatsHeatLevelRange? {
        guard level >= 0, level < levelCount else { return nil }
        switch level {
        case 0:
            return .zero
        case 1:
            return .below(thresholds[0])
        case levelCount - 1:
            return .from(thresholds[thresholds.count - 1])
        default:
            return .between(lower: thresholds[level - 2], upper: thresholds[level - 1])
        }
    }

    /// Сколько дней на каждой ступени (индекс — ступень, длина — `levelCount`): по суммам дней `totals`.
    /// Ступени вне легенды (у шкалы без границ — дни с тратами) не считаются.
    public func dayCounts(_ totals: some Sequence<Int64>) -> [Int] {
        var counts = Array(repeating: 0, count: levelCount)
        for total in totals {
            let level = level(forMinor: total)
            if level < counts.count {
                counts[level] += 1
            }
        }
        return counts
    }
}
