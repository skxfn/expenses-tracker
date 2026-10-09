import Foundation

extension StatisticsEngine {
    // MARK: - Категории с подкатегориями

    /// Разбивка периода по категориям верхнего уровня с подкатегориями.
    ///
    /// Порядок категорий — для списков и «Полос»: по сумме (при равенстве — больше трат, затем id),
    /// «Без категории» — всегда последней. Для кругов — `orderedByHue(_:hueRank:)`.
    /// - Parameter stepRank: номер ступени подкатегории среди сестёр (порядок создания — §8, п. 3).
    ///   Ступени знает каталог, а не траты, поэтому их передаёт вызывающий.
    public func groupBreakdown(
        for period: StatsPeriod,
        records: [ExpenseRecord],
        stepRank: [UUID: Int] = [:]
    ) -> [StatsGroupShare] {
        var groups: [UUID?: GroupAccumulator] = [:]
        var grandTotal: Int64 = 0
        for record in records where period.contains(record.date) {
            grandTotal += record.amountMinor
            groups[record.groupID, default: GroupAccumulator()].add(record)
        }
        return groups
            .map { groupID, group in
                StatsGroupShare(
                    groupID: groupID,
                    totalMinor: group.total,
                    count: group.count,
                    share: Self.share(group.total, of: grandTotal),
                    subcategories: group.subcategoryShares(stepRank: stepRank),
                    unassignedMinor: group.unassignedTotal,
                    unassignedCount: group.unassignedCount
                )
            }
            .sorted(by: Self.isGroupOrderedBefore)
    }

    /// Порядок для кругов («Кольцо», «Солнце»): по оттенку тона категории, при равном ранге — по сумме.
    /// Категории без ранга (цвет не из «Гуаши») — после ранжированных, «Без категории» — последней.
    /// - Parameter hueRank: `GouacheTone.hueRank` тона каждой категории; тоны знает каталог.
    public static func orderedByHue(_ groups: [StatsGroupShare], hueRank: [UUID: Int]) -> [StatsGroupShare] {
        groups.sorted { lhs, rhs in
            let left = lhs.groupID.map { hueRank[$0] ?? Int.max } ?? Int.max
            let right = rhs.groupID.map { hueRank[$0] ?? Int.max } ?? Int.max
            if (lhs.groupID == nil) != (rhs.groupID == nil) { return rhs.groupID == nil }
            if left != right { return left < right }
            return isGroupOrderedBefore(lhs, rhs)
        }
    }

    /// Сворачивание мелких категорий в «Ещё N»: категории с долей меньше `threshold` сворачиваются,
    /// только если таких хотя бы `minimumCount`. «Без категории» не сворачивается никогда.
    /// Порядок сохраняется, поэтому сворачивать можно и список по сумме, и порядок по оттенку.
    public static func fold(
        _ groups: [StatsGroupShare],
        threshold: Double = StatsThresholds.foldShare,
        minimumCount: Int = StatsThresholds.foldMinimumCount
    ) -> StatsFoldedGroups {
        let isSmall: (StatsGroupShare) -> Bool = { $0.groupID != nil && $0.share < threshold }
        guard groups.count(where: isSmall) >= minimumCount else {
            return StatsFoldedGroups(visible: groups, folded: [])
        }
        return StatsFoldedGroups(visible: groups.filter { !isSmall($0) }, folded: groups.filter(isSmall))
    }

    // MARK: - Внутреннее

    static func share(_ part: Int64, of total: Int64) -> Double {
        total == 0 ? 0 : Double(part) / Double(total)
    }

    private static func isGroupOrderedBefore(_ lhs: StatsGroupShare, _ rhs: StatsGroupShare) -> Bool {
        switch (lhs.groupID, rhs.groupID) {
        case (nil, .some): return false
        case (.some, nil): return true
        default: break
        }
        if lhs.totalMinor != rhs.totalMinor { return lhs.totalMinor > rhs.totalMinor }
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return (lhs.groupID?.uuidString ?? "") < (rhs.groupID?.uuidString ?? "")
    }
}

/// Накопитель одной категории верхнего уровня.
private struct GroupAccumulator {
    var total: Int64 = 0
    var count = 0
    var unassignedTotal: Int64 = 0
    var unassignedCount = 0
    var subcategories: [UUID: (total: Int64, count: Int)] = [:]

    mutating func add(_ record: ExpenseRecord) {
        total += record.amountMinor
        count += 1
        guard let categoryID = record.categoryID, categoryID != record.groupID else {
            unassignedTotal += record.amountMinor
            unassignedCount += 1
            return
        }
        subcategories[categoryID, default: (0, 0)].total += record.amountMinor
        subcategories[categoryID, default: (0, 0)].count += 1
    }

    func subcategoryShares(stepRank: [UUID: Int]) -> [StatsCategoryShare] {
        subcategories
            .map { id, sum in
                StatsCategoryShare(
                    categoryID: id,
                    totalMinor: sum.total,
                    count: sum.count,
                    share: StatisticsEngine.share(sum.total, of: total)
                )
            }
            .sorted { lhs, rhs in
                let left = lhs.categoryID.flatMap { stepRank[$0] } ?? Int.max
                let right = rhs.categoryID.flatMap { stepRank[$0] } ?? Int.max
                if left != right { return left < right }
                return StatisticsEngine.isOrderedBefore(lhs, rhs)
            }
    }
}
