import Foundation

/// Данные визуализаций категорий («Плитки · Полосы · Солнце · Кольцо»): разбивка периода
/// (`StatisticsEngine.groupBreakdown`) вместе с каталогом — имена, иконки, тоны, ступени.
///
/// Общие правила (DESIGN.md → Category Visualizations, INTEGRATION §4.6):
/// - категории < 3 % сворачиваются в «Ещё N», если таких хотя бы две; «Без категории» не сворачивается;
/// - списки, «Плитки» и «Полосы» — по сумме, круги — по оттенку; «Ещё N» и «Без категории» — в конце;
/// - внутри категории подкатегории идут по ступеням, «без подкатегории» — последней.
public struct CategoryVizData: Sendable, Hashable {
    /// Итог периода.
    public let totalMinor: Int64
    /// Трат в периоде.
    public let count: Int
    /// Все категории по сумме, «Без категории» последней — список под визуализацией.
    public let groups: [CategoryVizGroup]
    /// Части визуализации по сумме: видимые категории, «Ещё N», «Без категории».
    public let itemsBySum: [CategoryVizItem]
    /// Части визуализации по оттенку (круги): видимые категории, «Ещё N», «Без категории».
    public let itemsByHue: [CategoryVizItem]
    /// Свёрнутые категории; `nil` — сворачивать нечего.
    public let more: CategoryVizMore?

    public init(
        breakdown: [StatsGroupShare],
        catalog: CategoryCatalogSnapshot,
        foldThreshold: Double = StatsThresholds.foldShare,
        foldMinimumCount: Int = StatsThresholds.foldMinimumCount
    ) {
        let bySum = breakdown.sorted(by: Self.isOrderedBySum)
        let groups = bySum.map { CategoryVizGroup(share: $0, catalog: catalog) }
        let byID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let folded = StatisticsEngine.fold(bySum, threshold: foldThreshold, minimumCount: foldMinimumCount)
        let more = folded.folded.isEmpty ? nil : CategoryVizMore(groups: folded.folded.compactMap { byID[$0.groupID] })
        let hueOrder = StatisticsEngine.orderedByHue(folded.visible, hueRank: catalog.hueRank)

        self.totalMinor = breakdown.reduce(0) { $0 + $1.totalMinor }
        self.count = breakdown.reduce(0) { $0 + $1.count }
        self.groups = groups
        self.more = more
        self.itemsBySum = Self.items(folded.visible.compactMap { byID[$0.groupID] }, more: more)
        self.itemsByHue = Self.items(hueOrder.compactMap { byID[$0.groupID] }, more: more)
    }

    /// Нет трат за период.
    public var isEmpty: Bool { groups.isEmpty }

    /// Категория по id; `nil` в аргументе — «Без категории».
    public func group(_ id: UUID?) -> CategoryVizGroup? {
        groups.first { $0.id == id }
    }

    /// Категория, раскрытая в статистике: только существующая и с подкатегориями в каталоге.
    public func expandedGroup(_ id: UUID?) -> CategoryVizGroup? {
        guard let id, let group = group(id), group.isExpandable else { return nil }
        return group
    }

    /// Самая крупная категория — для «Больше всего — Продукты: 35%»; «Без категории» тоже в счёт
    /// («Больше всего — без категории: 18%»), при равенстве сумм — названная. `nil` — трат нет.
    public var largestGroup: CategoryVizGroup? { groups.max { $0.totalMinor < $1.totalMinor } }

    // MARK: - Внутреннее

    private static func items(_ visible: [CategoryVizGroup], more: CategoryVizMore?) -> [CategoryVizItem] {
        var items = visible.filter { !$0.isUncategorized }.map(CategoryVizItem.group)
        if let more { items.append(.more(more)) }
        items += visible.filter(\.isUncategorized).map(CategoryVizItem.group)
        return items
    }

    /// По сумме, при равенстве — больше трат, затем id; «Без категории» последней.
    private static func isOrderedBySum(_ lhs: StatsGroupShare, _ rhs: StatsGroupShare) -> Bool {
        if (lhs.groupID == nil) != (rhs.groupID == nil) { return rhs.groupID == nil }
        if lhs.totalMinor != rhs.totalMinor { return lhs.totalMinor > rhs.totalMinor }
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return (lhs.groupID?.uuidString ?? "") < (rhs.groupID?.uuidString ?? "")
    }
}

/// Категория верхнего уровня в визуализации.
public struct CategoryVizGroup: Sendable, Hashable, Identifiable {
    /// `nil` — «Без категории».
    public let id: UUID?
    /// `nil` — «Без категории» (имя из `copy.json` подставляет UI).
    public let name: String?
    /// Имя иконки MingCute; `nil` — «Без категории» (иконку выбирает UI).
    public let iconName: String?
    /// `nil` — нейтраль («Без категории» или цвет не из «Гуаши»).
    public let tone: GouacheTone?
    public let totalMinor: Int64
    public let count: Int
    /// Доля в итоге периода, 0…1.
    public let share: Double
    /// Подкатегории в каталоге: можно раскрыть; без них — «подкатегорий нет».
    public let hasSubcategories: Bool
    /// Подкатегории с тратами по ступеням, «без подкатегории» — последней. У «Без категории» — пусто.
    public let parts: [CategoryVizPart]

    public var isUncategorized: Bool { id == nil }
    /// Раскрывается до подкатегорий (шеврон в списке, тап в статистике).
    public var isExpandable: Bool { id != nil && (hasSubcategories || parts.contains { !$0.isUnassigned }) }
    /// Самая крупная часть — «Больше всего — Супермаркет: 69%».
    public var largestPart: CategoryVizPart? {
        parts.enumerated().max { lhs, rhs in
            lhs.element.totalMinor != rhs.element.totalMinor
                ? lhs.element.totalMinor < rhs.element.totalMinor
                : lhs.offset > rhs.offset
        }?.element
    }

    public init(
        id: UUID?,
        name: String?,
        iconName: String?,
        tone: GouacheTone?,
        totalMinor: Int64,
        count: Int,
        share: Double,
        hasSubcategories: Bool,
        parts: [CategoryVizPart]
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.tone = tone
        self.totalMinor = totalMinor
        self.count = count
        self.share = share
        self.hasSubcategories = hasSubcategories
        self.parts = parts
    }

    init(share group: StatsGroupShare, catalog: CategoryCatalogSnapshot) {
        let entry = group.groupID.flatMap { catalog[$0] }
        var parts = group.subcategories.compactMap { share -> CategoryVizPart? in
            guard let id = share.categoryID else { return nil }
            let sub = catalog[id]
            return CategoryVizPart(
                id: id,
                name: sub?.name ?? "",
                iconName: sub?.iconName ?? entry?.iconName,
                shadeStep: sub?.shadeStep ?? 0,
                totalMinor: share.totalMinor,
                count: share.count,
                share: share.share
            )
        }
        if group.groupID != nil, group.unassignedMinor > 0 {
            parts.append(CategoryVizPart(
                id: nil,
                name: nil,
                iconName: entry?.iconName,
                shadeStep: nil,
                totalMinor: group.unassignedMinor,
                count: group.unassignedCount,
                share: group.unassignedShare
            ))
        }
        self.init(
            id: group.groupID,
            name: group.groupID == nil ? nil : (entry?.name ?? ""),
            iconName: group.groupID == nil ? nil : entry?.iconName,
            tone: entry?.tone,
            totalMinor: group.totalMinor,
            count: group.count,
            share: group.share,
            hasSubcategories: (entry?.subcategoryCount ?? 0) > 0,
            parts: group.groupID == nil ? [] : parts
        )
    }
}

/// Часть категории: подкатегория или траты «без подкатегории».
public struct CategoryVizPart: Sendable, Hashable, Identifiable {
    /// id подкатегории; `nil` — «без подкатегории».
    public let id: UUID?
    /// `nil` — «без подкатегории» (`viz.noSubLegend`).
    public let name: String?
    /// Иконка подкатегории; у «без подкатегории» — иконка категории.
    public let iconName: String?
    /// Ступень оттенка; `nil` — «без подкатегории» (штриховка).
    public let shadeStep: Int?
    public let totalMinor: Int64
    public let count: Int
    /// Доля в итоге категории, 0…1 («69% категории»).
    public let share: Double

    public var isUnassigned: Bool { id == nil }

    public init(
        id: UUID?,
        name: String?,
        iconName: String?,
        shadeStep: Int?,
        totalMinor: Int64,
        count: Int,
        share: Double
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.shadeStep = shadeStep
        self.totalMinor = totalMinor
        self.count = count
        self.share = share
    }
}

/// «Ещё N»: свёрнутые мелкие категории.
public struct CategoryVizMore: Sendable, Hashable {
    /// Свёрнутые категории по сумме.
    public let groups: [CategoryVizGroup]

    public init(groups: [CategoryVizGroup]) {
        self.groups = groups
    }

    public var totalMinor: Int64 { groups.reduce(0) { $0 + $1.totalMinor } }
    public var count: Int { groups.reduce(0) { $0 + $1.count } }
    public var share: Double { groups.reduce(0) { $0 + $1.share } }
}

/// Часть визуализации: категория (в т. ч. «Без категории») или «Ещё N».
public enum CategoryVizItem: Sendable, Hashable, Identifiable {
    case group(CategoryVizGroup)
    case more(CategoryVizMore)

    public var id: CategoryVizItemID {
        switch self {
        case .group(let group): group.id.map(CategoryVizItemID.category) ?? .uncategorized
        case .more: .more
        }
    }

    public var totalMinor: Int64 {
        switch self {
        case .group(let group): group.totalMinor
        case .more(let more): more.totalMinor
        }
    }

    public var share: Double {
        switch self {
        case .group(let group): group.share
        case .more(let more): more.share
        }
    }
}

/// Что выбрали в визуализации — для колбэка экрана.
public enum CategoryVizItemID: Sendable, Hashable {
    case category(UUID)
    case uncategorized
    case more
}
