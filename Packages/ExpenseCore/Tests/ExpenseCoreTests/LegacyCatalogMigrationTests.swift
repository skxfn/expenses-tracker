import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

@Suite struct LegacyCatalogMigrationTests {
    private func migrationJSON() throws -> [String: Any] {
        try #require(try RepositoryFiles.json("design/migration.json") as? [String: Any])
    }

    // MARK: - Таблицы совпадают с design/migration.json

    @Test func colorTableMatchesJSON() throws {
        let colors = try #require(try migrationJSON()["colors"] as? [[String: String]])
        #expect(LegacyCatalogMigration.colorTable.count == colors.count)
        for entry in colors {
            let old = try #require(entry["old"])
            let tone = try #require(LegacyCatalogMigration.colorTable[old.uppercased()], "\(old)")
            #expect(tone.rawValue == entry["new"])
            #expect(tone.mainHex == entry["newHex"]?.uppercased())
        }
    }

    @Test func iconTableMatchesJSON() throws {
        let json = try migrationJSON()
        let icons = try #require(json["icons"] as? [[String: String]])
        #expect(LegacyCatalogMigration.iconTable.count == icons.count)
        for entry in icons {
            let symbol = try #require(entry["sfSymbol"])
            #expect(LegacyCatalogMigration.iconTable[symbol] == entry["mingcute"], "\(symbol)")
        }
        #expect(LegacyCatalogMigration.iconFallback == json["iconFallback"] as? String)
    }

    @Test func legacyDefaultsMatchJSON() throws {
        let entries = try #require(try migrationJSON()["defaultCategories"] as? [[String: String]])
        let legacy = LegacyCatalogMigration.legacyDefaults
        #expect(legacy.count == entries.count)
        for (item, entry) in zip(legacy, entries) {
            #expect(item.oldName == entry["oldName"])
            #expect(item.oldIcon == entry["oldIcon"])
            #expect(item.template.name == entry["newName"])
            // Цвет базовой категории — всегда по таблице colors, и она даёт её тон.
            let oldColor = try #require(entry["oldColor"])
            #expect(LegacyCatalogMigration.tone(forLegacy: oldColor) == item.template.tone, "\(oldColor)")
        }
    }

    // MARK: - Цвета

    /// `colorFallbackRule`: «Правило на 15 старых цветах даёт ту же таблицу, кроме #DD6B20 (по правилу kinovar)».
    @Test func fallbackRuleReproducesTableExceptApricot() {
        for (hex, tone) in LegacyCatalogMigration.colorTable {
            let expected: GouacheTone = hex == "#DD6B20" ? .kinovar : tone
            #expect(LegacyCatalogMigration.nearestTone(to: hex) == expected, "\(hex)")
        }
    }

    @Test(arguments: [
        ("#e5484d", GouacheTone.kinovar),
        ("#3e9b6b", .shalfey),
        ("#798DA3", .slanets),
        ("#797875", .grafit),
        ("#34C759", .shalfey),
        ("#007AFF", .kobalt),
        ("#FFCC00", .okhra),
        ("#8E8E93", .grafit),
        ("#808080", .grafit),
        ("красный", .grafit),
        ("", .grafit)
    ])
    func toneForLegacyColor(hex: String, tone: GouacheTone) {
        #expect(LegacyCatalogMigration.tone(forLegacy: hex) == tone)
        #expect(LegacyCatalogMigration.colorHex(forLegacy: hex) == tone.mainHex)
    }

    /// Новые значения не меняются: повторный перевод ничего не делает.
    @Test func colorMigrationIsIdempotent() {
        for tone in GouacheTone.allCases {
            #expect(LegacyCatalogMigration.tone(forLegacy: tone.mainHex) == tone)
        }
        for hex in LegacyCatalogMigration.colorTable.keys {
            let once = LegacyCatalogMigration.colorHex(forLegacy: hex)
            #expect(LegacyCatalogMigration.colorHex(forLegacy: once) == once)
        }
    }

    // MARK: - Иконки

    @Test(arguments: [
        ("cart.fill", "Продукты", "basket-fill"),
        ("cart.fill", "  продукты ", "basket-fill"),
        ("cart.fill", "Еда", "shopping-cart-1-fill"),
        ("cross.case.fill", "Здоровье", "capsule-fill"),
        ("cross.case.fill", "Аптечка", "first-aid-kit-fill"),
        ("bus.fill", "Продукты", "bus-fill"),
        ("bolt.fill", "Свет", "bulb-fill"),
        ("star.fill", "Звёзды", "more-3-fill"),
        ("questionmark", "Другое", "more-3-fill"),
        ("teacup-fill", "Кофе", "teacup-fill"),
        ("basket-fill", "Продукты", "basket-fill")
    ])
    func iconForLegacyName(symbol: String, categoryName: String, expected: String) {
        #expect(LegacyCatalogMigration.iconName(forLegacy: symbol, categoryName: categoryName) == expected)
    }

    @Test func iconMigrationIsIdempotent() {
        for (symbol, _) in LegacyCatalogMigration.iconTable {
            let once = LegacyCatalogMigration.iconName(forLegacy: symbol, categoryName: "Продукты")
            #expect(CategoryIconCatalog.contains(once))
            #expect(LegacyCatalogMigration.iconName(forLegacy: once, categoryName: "Продукты") == once)
        }
    }

    // MARK: - Перевод категорий в контексте

    @Test func applyMigratesCategoriesAndRenamesOnlyUntouchedDefaults() throws {
        let context = ModelContext(try ModelContainerFactory.make(inMemory: true))
        let cafe = insert("Кафе и рестораны", icon: "fork.knife", color: "#DD6B20", order: 0, in: context)
        let home = insert("жильё и жкх ", icon: "sofa.fill", color: "#A0674B", order: 1, in: context)
        let net = insert("Связь и интернет", icon: "wifi", color: "#0B93B8", order: 2, in: context)
        // «Связь» уже занята пользовательской категорией: «Связь и интернет» не переименовывается.
        let custom = insert("связь", icon: "iphone", color: "#123456", order: 3, in: context)
        let food = insert("Продукты", icon: "cart.fill", color: "#2E9D63", order: 4, in: context)
        let other = insert("Мелочи", icon: "star.fill", color: "#8E8E93", order: 5, in: context)
        try context.save()

        try LegacyCatalogMigration.apply(in: context)

        #expect(snapshot(cafe) == .init(name: "Кафе", icon: "fork-knife-fill", color: GouacheTone.abrikos.mainHex))
        #expect(snapshot(home) == .init(name: "Дом", icon: "sofa-fill", color: GouacheTone.umbra.mainHex))
        #expect(snapshot(net) == .init(name: "Связь и интернет", icon: "wifi-fill", color: GouacheTone.tseruleum.mainHex))
        #expect(snapshot(custom) == .init(name: "связь", icon: "cellphone-fill", color: LegacyCatalogMigration.colorHex(forLegacy: "#123456")))
        #expect(snapshot(food) == .init(name: "Продукты", icon: "basket-fill", color: GouacheTone.shalfey.mainHex))
        #expect(snapshot(other) == .init(name: "Мелочи", icon: "more-3-fill", color: GouacheTone.grafit.mainHex))
        #expect(!context.hasChanges)

        // Повторный проход ничего не меняет.
        let before = [cafe, home, net, custom, food, other].map(snapshot)
        try LegacyCatalogMigration.apply(in: context)
        #expect([cafe, home, net, custom, food, other].map(snapshot) == before)
    }

    /// Два «Кафе и рестораны» (например, одна в архиве): новое имя получает только первая.
    @Test func applyDoesNotCreateDuplicateNames() throws {
        let context = ModelContext(try ModelContainerFactory.make(inMemory: true))
        let first = insert("Кафе и рестораны", icon: "fork.knife", color: "#DD6B20", order: 0, in: context)
        let second = insert("Кафе и рестораны", icon: "fork.knife", color: "#DD6B20", order: 1, in: context)
        second.isArchived = true
        try context.save()

        try LegacyCatalogMigration.apply(in: context)

        #expect(first.name == "Кафе")
        #expect(second.name == "Кафе и рестораны")
    }

    // MARK: - Помощники

    private struct Snapshot: Equatable {
        let name: String
        let icon: String
        let color: String
    }

    private func snapshot(_ category: ExpenseCategory) -> Snapshot {
        Snapshot(name: category.name, icon: category.iconName, color: category.colorHex)
    }

    @discardableResult
    private func insert(_ name: String, icon: String, color: String, order: Int, in context: ModelContext) -> ExpenseCategory {
        let category = ExpenseCategory(name: name, iconName: icon, colorHex: color, sortOrder: order)
        context.insert(category)
        return category
    }
}
