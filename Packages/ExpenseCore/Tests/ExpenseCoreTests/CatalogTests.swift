import Foundation
import Testing
@testable import ExpenseCore

struct CatalogTests {
    // MARK: - Базовые категории

    @Test func defaultCategoriesMatchMigrationJSON() throws {
        let migration = try #require(try RepositoryFiles.json("design/migration.json") as? [String: Any])
        let entries = try #require(migration["defaultCategories"] as? [[String: String]])

        #expect(DefaultCategories.all.map(\.name) == entries.map { $0["newName"] })
        #expect(DefaultCategories.all.map(\.tone.rawValue) == entries.map { $0["tone"] })
        #expect(DefaultCategories.all.map(\.iconName) == entries.map { $0["icon"] })
    }

    @Test func defaultCategoriesAreUniqueAndUseCatalog() {
        let all = DefaultCategories.all
        #expect(all.count == 12)
        #expect(Set(all.map { $0.name.lowercased() }).count == all.count)
        #expect(Set(all.map(\.tone)).count == all.count)
        for template in all {
            #expect(CategoryIconCatalog.contains(template.iconName), "\(template.name)")
            #expect(template.colorHex == template.tone.mainHex)
        }
    }

    // MARK: - Иконки

    @Test func iconCatalogHasNineGroupsWithUniqueNames() throws {
        let names = CategoryIconCatalog.allNames
        #expect(Set(names).count == names.count)
        #expect(CategoryIconCatalog.groups.map(\.titleKey) == (1...9).map { "cat.icon.group.\($0)" })
        #expect(CategoryIconCatalog.groups.allSatisfy { $0.icons.count >= 6 })
        #expect(names.allSatisfy { $0.hasSuffix("-fill") && !$0.contains(".") })

        // Подзаголовки групп — одна строка copy.json через « · ».
        let titles = try #require(try RepositoryFiles.copyFinals()["cat.icon.groups"])
        #expect(titles.components(separatedBy: " · ").count == CategoryIconCatalog.groups.count)
    }

    /// Каталог покрывает все иконки, в которые переводятся данные прошлой версии.
    @Test func iconCatalogContainsEveryMigrationIcon() throws {
        let migration = try #require(try RepositoryFiles.json("design/migration.json") as? [String: Any])
        let icons = try #require(migration["icons"] as? [[String: String]]).compactMap { $0["mingcute"] }
        let defaults = try #require(migration["defaultCategories"] as? [[String: String]]).compactMap { $0["icon"] }
        let fallback = try #require(migration["iconFallback"] as? String)

        for name in icons + defaults + [fallback] {
            #expect(CategoryIconCatalog.contains(name), "\(name)")
        }
    }

    /// Ключи VoiceOver совпадают со строками `cat.icon.name.*` в copy.json; ключей без строки —
    /// ровно иконки, добавленные ради данных прошлой версии (их нет в макете).
    @Test func iconAccessibilityKeysMatchCopyJSON() throws {
        let copyKeys = try Self.expandedIconNameKeys(try RepositoryFiles.copyFinals())
        let catalogIcons = CategoryIconCatalog.groups.flatMap(\.icons)
        let keys = catalogIcons.map(\.accessibilityKey)

        #expect(Set(keys).count == keys.count)
        #expect(copyKeys.count == 60)
        #expect(copyKeys.isSubset(of: Set(keys)))

        let migration = try #require(try RepositoryFiles.json("design/migration.json") as? [String: Any])
        let migrationIcons = Set(try #require(migration["icons"] as? [[String: String]]).compactMap { $0["mingcute"] })
        for icon in catalogIcons where !copyKeys.contains(icon.accessibilityKey) {
            #expect(migrationIcons.contains(icon.name), "\(icon.name) нет ни в макете, ни в migration.json")
        }
    }

    /// Ассеты MingCute лежат в `App/Resources/Assets.xcassets/Categories/<имя>.imageset`.
    @Test func everyCatalogIconHasImageset() {
        let folder = RepositoryFiles.root.appending(path: "App/Resources/Assets.xcassets/Categories")
        for name in CategoryIconCatalog.allNames {
            let path = folder.appending(path: "\(name).imageset").path(percentEncoded: false)
            #expect(FileManager.default.fileExists(atPath: path), "\(name)")
        }
    }

    /// `cat.icon.name.<группа>.<номер>` из id copy.json: `1.*` (все по порядку), `6.1` (одна),
    /// `8.1-3` (диапазон); `*` после явных номеров занимает оставшиеся номера по порядку.
    static func expandedIconNameKeys(_ finals: [String: String]) throws -> Set<String> {
        let prefix = "cat.icon.name."
        var explicit: [Int: [Int]] = [:]
        var rest: [Int: Int] = [:]
        for (id, final) in finals where id.hasPrefix(prefix) {
            let parts = id.dropFirst(prefix.count).split(separator: ".")
            let group = try #require(Int(parts[0]), "\(id)")
            let count = final.components(separatedBy: " · ").count
            switch parts[1] {
            case "*":
                rest[group] = count
            case let range where range.contains("-"):
                let bounds = range.split(separator: "-").compactMap { Int($0) }
                try #require(bounds.count == 2 && bounds[1] - bounds[0] + 1 == count, "\(id)")
                explicit[group, default: []] += Array(bounds[0]...bounds[1])
            default:
                explicit[group, default: []].append(try #require(Int(parts[1]), "\(id)"))
            }
        }
        var keys = Set<String>()
        for group in Set(explicit.keys).union(rest.keys) {
            var numbers = Set(explicit[group] ?? [])
            var next = 1
            for _ in 0..<(rest[group] ?? 0) {
                while numbers.contains(next) { next += 1 }
                numbers.insert(next)
            }
            keys.formUnion(numbers.map { "\(prefix)\(group).\($0)" })
        }
        return keys
    }

    // MARK: - HexColor

    @Test(arguments: ["#FFFFFF", "#000000", "#2e9d63", "#A0674B"])
    func hexColorAcceptsValid(hex: String) {
        #expect(HexColor.isValid(hex))
    }

    @Test(arguments: ["", "#", "FFFFFF", "#FFF", "#FFFFFFF", "#GGGGGG", "#+FFFFF", "#-00000", " #FFFFFF", "#ＦＦＦＦＦＦ"])
    func hexColorRejectsInvalid(hex: String) {
        #expect(!HexColor.isValid(hex))
    }

    @Test func hexColorComponents() throws {
        let rgb = try #require(HexColor.components("#FF8000"))
        #expect(rgb.red == 1)
        #expect(rgb.green == 128.0 / 255)
        #expect(rgb.blue == 0)
    }
}
