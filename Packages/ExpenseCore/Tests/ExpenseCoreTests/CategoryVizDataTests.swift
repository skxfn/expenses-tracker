import Foundation
import Testing
@testable import ExpenseCore

/// Данные визуализаций категорий: каталог, части, «Ещё N», порядки.
@Suite struct CategoryVizDataTests {
    private typealias F = StatsFixture
    private let engine = F.engine

    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    // Продукты (Шалфей) с подкатегориями «Супермаркет», «Рынок»; Кафе (Абрикос) без подкатегорий;
    // Здоровье (Киноварь) и Связь (Церулеум) — мелкие.
    private static let food = id(1), cafe = id(2), health = id(3), net = id(4)
    private static let market = id(11), bazaar = id(12)

    private static let catalog = CategoryCatalogSnapshot([
        .init(id: food, name: "Продукты", iconName: "basket-fill", tone: .shalfey, subcategoryCount: 2),
        .init(id: market, name: "Супермаркет", iconName: "shopping-cart-1-fill", tone: .shalfey,
              parentID: food, siblingPosition: 0),
        .init(id: bazaar, name: "Рынок", iconName: "apple-fruit-fill", tone: .shalfey,
              parentID: food, siblingPosition: 1),
        .init(id: cafe, name: "Кафе", iconName: "fork-knife-fill", tone: .abrikos),
        .init(id: health, name: "Здоровье", iconName: "capsule-fill", tone: .kinovar),
        .init(id: net, name: "Связь", iconName: "wifi-fill", tone: .tseruleum)
    ])

    private func record(_ amount: Int64, _ category: UUID?, group: UUID? = nil) -> ExpenseRecord {
        ExpenseRecord(amountMinor: amount, date: F.now, categoryID: category, groupID: group)
    }

    private func data(_ records: [ExpenseRecord]) -> CategoryVizData {
        let breakdown = engine.groupBreakdown(for: F.october, records: records, stepRank: Self.catalog.stepRank)
        return CategoryVizData(breakdown: breakdown, catalog: Self.catalog)
    }

    /// Продукты 6 000 (рынок 1 000, супермаркет 3 000, без подкатегории 2 000), кафе 3 500,
    /// здоровье 200, связь 100, без категории 200 → итог 10 000.
    private var records: [ExpenseRecord] {
        [
            record(1_000, Self.bazaar, group: Self.food),
            record(3_000, Self.market, group: Self.food),
            record(2_000, Self.food),
            record(3_500, Self.cafe),
            record(200, Self.health),
            record(100, Self.net),
            record(200, nil)
        ]
    }

    @Test func groupsCarryCatalogAndParts() throws {
        let data = data(records)
        #expect(data.totalMinor == 10_000)
        #expect(data.count == 7)
        let order: [UUID?] = [Self.food, Self.cafe, Self.health, Self.net, nil]
        #expect(data.groups.map(\.id) == order)

        let food = try #require(data.group(Self.food))
        #expect(food.name == "Продукты")
        #expect(food.tone == .shalfey)
        #expect(food.hasSubcategories)
        #expect(food.isExpandable)
        // По ступеням, «без подкатегории» — последней; доля — от итога категории.
        let partIDs: [UUID?] = [Self.market, Self.bazaar, nil]
        #expect(food.parts.map(\.id) == partIDs)
        let steps: [Int?] = [0, 1, nil]
        #expect(food.parts.map(\.shadeStep) == steps)
        let shares: [Double] = [0.5, 1.0 / 6, 2.0 / 6]
        #expect(food.parts.map(\.share) == shares)
        #expect(food.parts.last?.iconName == "basket-fill")
        #expect(food.largestPart?.id == Self.market)

        let cafe = try #require(data.group(Self.cafe))
        #expect(!cafe.hasSubcategories)
        #expect(!cafe.isExpandable)
        #expect(cafe.parts.map(\.id) == [UUID?.none])

        let uncategorized = try #require(data.group(nil))
        #expect(uncategorized.isUncategorized)
        #expect(uncategorized.name == nil)
        #expect(uncategorized.parts.isEmpty)
        #expect(data.expandedGroup(Self.food)?.id == Self.food)
        #expect(data.expandedGroup(Self.cafe) == nil)
        #expect(data.largestGroup?.id == Self.food)
    }

    @Test func smallGroupsFoldIntoMoreBeforeUncategorized() throws {
        let data = data(records)
        let more = try #require(data.more)
        // Здоровье 2 % и Связь 1 % — две категории меньше 3 %; «Без категории» не сворачивается.
        let folded: [UUID?] = [Self.health, Self.net]
        #expect(more.groups.map(\.id) == folded)
        #expect(more.totalMinor == 300)
        #expect(abs(more.share - 0.03) < 1e-12)
        let expected: [CategoryVizItemID] = [.category(Self.food), .category(Self.cafe), .more, .uncategorized]
        #expect(data.itemsBySum.map(\.id) == expected)
        // Список под визуализацией — все категории.
        #expect(data.groups.count == 5)
    }

    @Test func singleSmallGroupIsNotFolded() {
        let data = data(records.filter { $0.categoryID != Self.net })
        #expect(data.more == nil)
        let expected: [CategoryVizItemID] = [.category(Self.food), .category(Self.cafe), .category(Self.health), .uncategorized]
        #expect(data.itemsBySum.map(\.id) == expected)
    }

    @Test func circlesFollowHueOrder() {
        let data = data(records.filter { $0.categoryID != Self.net })
        // Киноварь → Абрикос → Шалфей по оттенку, «Без категории» последней.
        let expected: [CategoryVizItemID] = [.category(Self.health), .category(Self.cafe), .category(Self.food), .uncategorized]
        #expect(data.itemsByHue.map(\.id) == expected)
    }

    @Test func emptyPeriod() {
        let data = data([])
        #expect(data.isEmpty)
        #expect(data.totalMinor == 0)
        #expect(data.itemsBySum.isEmpty)
        #expect(data.more == nil)
        #expect(data.largestGroup == nil)
    }

    @Test func snapshotFromModelsOrdersShadesAndInheritsTone() throws {
        let food = ExpenseCategory(name: "Продукты", iconName: "basket-fill", colorHex: GouacheTone.shalfey.mainHex, sortOrder: 0)
        let late = ExpenseCategory(name: "Рынок", iconName: "apple-fruit-fill", colorHex: food.colorHex, sortOrder: 5, parent: food)
        let early = ExpenseCategory(name: "Супермаркет", iconName: "shopping-cart-1-fill", colorHex: food.colorHex, sortOrder: 1, parent: food)
        food.children = [late, early]
        let other = ExpenseCategory(name: "Своё", iconName: "tag-fill", colorHex: "#123456", sortOrder: 1)

        let snapshot = CategoryCatalogSnapshot(categories: [early, food, other])
        #expect(snapshot.entries.count == 4)
        #expect(snapshot[food.id]?.subcategoryCount == 2)
        #expect(snapshot[early.id]?.siblingPosition == 0)
        #expect(snapshot[late.id]?.siblingPosition == 1)
        #expect(snapshot[late.id]?.tone == .shalfey)
        #expect(snapshot[late.id]?.parentID == food.id)
        #expect(snapshot.stepRank == [early.id: 0, late.id: 1])
        #expect(snapshot.hueRank == [food.id: GouacheTone.shalfey.hueRank])
        #expect(snapshot[other.id]?.tone == nil)
    }

    @Test func shadeStepRepeatsAfterFive() {
        let entry = CategoryCatalogSnapshot.Entry(
            id: UUID(), name: "", iconName: "", tone: .kobalt, parentID: UUID(), siblingPosition: 6
        )
        #expect(entry.shadeStep == 1)
    }
}
