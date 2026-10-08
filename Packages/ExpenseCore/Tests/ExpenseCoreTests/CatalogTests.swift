import Foundation
import Testing
@testable import ExpenseCore
#if canImport(AppKit)
import AppKit
#endif

struct CatalogTests {
    // MARK: - Базовые категории

    @Test func defaultCategoriesAreUniqueAndUseCatalogs() {
        let all = DefaultCategories.all
        #expect(all.count == 12)
        #expect(Set(all.map { $0.name.lowercased() }).count == all.count)
        #expect(Set(all.map(\.colorHex)).count == all.count)
        for template in all {
            #expect(CategoryIconCatalog.allSymbols.contains(template.iconName), "\(template.name)")
            #expect(CategoryPalette.colors.contains(template.colorHex), "\(template.name)")
        }
    }

    // MARK: - Иконки

    @Test func iconCatalogHasUniqueSymbolsAndTitles() {
        let symbols = CategoryIconCatalog.allSymbols
        #expect((50...70).contains(symbols.count))
        #expect(Set(symbols).count == symbols.count)

        let titles = CategoryIconCatalog.groups.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(CategoryIconCatalog.groups.allSatisfy { !$0.title.isEmpty && !$0.symbols.isEmpty })
    }

    #if canImport(AppKit)
    @Test func allIconsExistInSFSymbols() {
        for name in CategoryIconCatalog.allSymbols {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }

    /// Метаданные SF Symbols системы: имя → год выпуска → версия iOS.
    /// Проверяет, что иконки не новее iOS 17 (на маке может стоять более новый набор символов).
    @Test(.enabled(if: FileManager.default.fileExists(atPath: Self.symbolAvailabilityPath)))
    func allIconsAvailableOnIOS17() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: Self.symbolAvailabilityPath))
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let symbols = try #require(plist["symbols"] as? [String: String])
        let releases = try #require(plist["year_to_release"] as? [String: [String: String]])

        for name in CategoryIconCatalog.allSymbols {
            let iOSVersion = symbols[name].flatMap { releases[$0]?["iOS"] }
            let version = try #require(iOSVersion, "Нет данных о доступности \(name)")
            #expect(
                version.compare("17.0", options: .numeric) != .orderedDescending,
                "\(name) появился в iOS \(version)"
            )
        }
    }

    static let symbolAvailabilityPath =
        "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist"
    #endif

    // MARK: - Палитра

    @Test func paletteColorsAreValidAndUnique() {
        let colors = CategoryPalette.colors
        #expect((12...16).contains(colors.count))
        #expect(Set(colors.map { $0.uppercased() }).count == colors.count)
        for hex in colors {
            #expect(HexColor.isValid(hex), "\(hex)")
        }
    }

    /// Контраст не ниже 3:1 (WCAG для графики) и к белому, и к чёрному фону.
    @Test func paletteColorsReadableInLightAndDarkThemes() throws {
        for hex in CategoryPalette.colors {
            let luminance = try relativeLuminance(hex)
            let onWhite = 1.05 / (luminance + 0.05)
            let onBlack = (luminance + 0.05) / 0.05
            #expect(onWhite >= 3, "\(hex) на белом: \(onWhite)")
            #expect(onBlack >= 3, "\(hex) на чёрном: \(onBlack)")
        }
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

    private func relativeLuminance(_ hex: String) throws -> Double {
        let rgb = try #require(HexColor.components(hex))
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }
}
