import Foundation

/// Снимок каталога категорий для статистики и визуализаций: значения без ссылок на SwiftData.
/// Траты знают только id категорий; имена, иконки, тоны и ступени оттенков берутся отсюда.
public struct CategoryCatalogSnapshot: Sendable, Hashable {
    /// Категория или подкатегория каталога.
    public struct Entry: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let name: String
        /// Имя иконки MingCute.
        public let iconName: String
        /// Тон категории верхнего уровня; у подкатегории — тон родителя. `nil` — цвет не из «Гуаши».
        public let tone: GouacheTone?
        /// `nil` — категория верхнего уровня.
        public let parentID: UUID?
        /// Позиция подкатегории среди сестёр в порядке ступеней (`SubcategoryShades.ordered`);
        /// у категории верхнего уровня — `nil`.
        public let siblingPosition: Int?
        /// Подкатегорий в каталоге, включая архивные; у подкатегории — 0.
        public let subcategoryCount: Int

        public init(
            id: UUID,
            name: String,
            iconName: String,
            tone: GouacheTone?,
            parentID: UUID? = nil,
            siblingPosition: Int? = nil,
            subcategoryCount: Int = 0
        ) {
            self.id = id
            self.name = name
            self.iconName = iconName
            self.tone = tone
            self.parentID = parentID
            self.siblingPosition = siblingPosition
            self.subcategoryCount = subcategoryCount
        }

        /// Ступень оттенка подкатегории (0…`SubcategoryShades.stepCount - 1`); `nil` — категория.
        public var shadeStep: Int? { siblingPosition.map(SubcategoryShades.step(forPosition:)) }
    }

    public let entries: [UUID: Entry]

    public init(_ entries: [Entry]) {
        self.entries = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Снимок из моделей. Подкатегории категорий верхнего уровня добавляются сами, архивные тоже:
    /// по ним могут быть траты периода. Вызывать в контексте (акторе), которому принадлежат модели.
    public init(categories: [ExpenseCategory]) {
        var entries: [UUID: Entry] = [:]
        for category in categories {
            let group = category.parent ?? category
            guard entries[group.id] == nil else { continue }
            let tone = GouacheTone(mainHex: group.colorHex)
            let children = SubcategoryShades.ordered(group.children)
            entries[group.id] = Entry(
                id: group.id,
                name: group.name,
                iconName: group.iconName,
                tone: tone,
                subcategoryCount: children.count
            )
            for (position, child) in children.enumerated() {
                entries[child.id] = Entry(
                    id: child.id,
                    name: child.name,
                    iconName: child.iconName,
                    tone: tone,
                    parentID: group.id,
                    siblingPosition: position
                )
            }
        }
        self.entries = entries
    }

    public subscript(id: UUID) -> Entry? { entries[id] }

    /// Ранги ступеней подкатегорий — для `StatisticsEngine.groupBreakdown(for:records:stepRank:)`.
    public var stepRank: [UUID: Int] {
        entries.compactMapValues(\.siblingPosition)
    }

    /// Ранги оттенков категорий верхнего уровня — для `StatisticsEngine.orderedByHue(_:hueRank:)`.
    public var hueRank: [UUID: Int] {
        entries.compactMapValues { $0.parentID == nil ? $0.tone?.hueRank : nil }
    }
}
