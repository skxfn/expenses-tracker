import Foundation

/// Что выбрано в разделе «Категории» статистики: категория (с подкатегориями или без), «Без категории»,
/// подкатегория или траты категории «без подкатегории». Выбор фильтрует сводку, журнал трат и все блоки
/// под «Категориями» (`filter`); категория с подкатегориями при этом раскрывается до них.
public enum StatsCategorySelection: Sendable, Hashable {
    /// Категория верхнего уровня вместе с подкатегориями.
    case group(UUID)
    /// Траты без категории.
    case uncategorized
    /// Подкатегория `id` категории `groupID`.
    case subcategory(UUID, groupID: UUID)
    /// Траты категории `groupID`, записанные без подкатегории.
    case unassigned(groupID: UUID)

    /// Выбор категории визуализации: названная — `.group`, «Без категории» — `.uncategorized`.
    public init(_ group: CategoryVizGroup) {
        self = group.id.map(StatsCategorySelection.group) ?? .uncategorized
    }

    /// Выбор части категории; `nil` — у «Без категории» частей нет.
    public init?(_ part: CategoryVizPart, of group: CategoryVizGroup) {
        guard let groupID = group.id else { return nil }
        self = part.id.map { .subcategory($0, groupID: groupID) } ?? .unassigned(groupID: groupID)
    }

    /// Категория верхнего уровня; `nil` — «Без категории».
    public var groupID: UUID? {
        switch self {
        case .group(let id), .subcategory(_, let id), .unassigned(let id): id
        case .uncategorized: nil
        }
    }

    /// Выбрана часть категории, а не категория целиком.
    public var isPart: Bool {
        switch self {
        case .subcategory, .unassigned: true
        case .group, .uncategorized: false
        }
    }

    /// Та же категория целиком: у части — её категория, у категории — она сама.
    public var whole: StatsCategorySelection {
        groupID.map(StatsCategorySelection.group) ?? .uncategorized
    }

    /// Фильтр трат: «без подкатегории» — траты, записанные прямо в категорию (`.category` её id).
    public var filter: StatsCategoryFilter {
        switch self {
        case .group(let id): .group(id)
        case .uncategorized: .uncategorized
        case .subcategory(let id, _): .category(id)
        case .unassigned(let groupID): .category(groupID)
        }
    }

    /// Выбрана ли эта часть категории.
    public func isSelected(_ part: CategoryVizPart) -> Bool {
        switch self {
        case .subcategory(let id, _): part.id == id
        case .unassigned: part.isUnassigned
        case .group, .uncategorized: false
        }
    }
}

extension CategoryVizData {
    /// Выбор, приведённый к данным периода: категории без трат в периоде нет — выбора нет; части без трат нет —
    /// выбрана её категория целиком.
    public func resolved(_ selection: StatsCategorySelection?) -> StatsCategorySelection? {
        guard let selection, let group = group(selection.groupID) else { return nil }
        guard selection.isPart else { return selection }
        return group.parts.contains(where: selection.isSelected) ? selection : selection.whole
    }

    /// Выбранная категория (для части — её категория); `nil` — выбора нет или категории нет в периоде.
    public func group(for selection: StatsCategorySelection?) -> CategoryVizGroup? {
        resolved(selection).flatMap { group($0.groupID) }
    }

    /// Выбранная часть категории; `nil` — выбрана категория целиком или части нет в периоде.
    public func part(for selection: StatsCategorySelection?) -> CategoryVizPart? {
        guard let selection = resolved(selection), selection.isPart else { return nil }
        return group(selection.groupID)?.parts.first(where: selection.isSelected)
    }
}
