import Foundation
import Testing
@testable import ExpenseCore

@Suite struct SettingsKeysTests {
    /// Значения лежат в UserDefaults: rawValue менять нельзя, иначе выбор пользователя сбросится.
    @Test func viewStyleRawValuesAreStable() {
        #expect(HomeOverviewStyle.allCases.map(\.rawValue) == ["tiles", "ring"])
        #expect(StatsCategoryView.allCases.map(\.rawValue) == ["tiles", "strips", "sun", "ring"])
        #expect(HomeOverviewStyle.default == .tiles)
        #expect(StatsCategoryView.default == .tiles)
        #expect(CurrencySymbolStyle.allCases.map(\.rawValue) == ["sign", "code"])
        #expect(CurrencySymbolStyle.default == .sign)
    }

    @Test func keysAreUnique() {
        let keys = [
            SettingsKeys.currencyCode, SettingsKeys.currencySymbolStyle, SettingsKeys.didSeedDefaultCategories,
            SettingsKeys.homeOverviewStyle, SettingsKeys.statsCategoryView
        ]
        #expect(Set(keys).count == keys.count)
    }

    @Test func styleRoundTripsThroughDefaults() throws {
        let temporary = try TemporaryDefaults()
        temporary.defaults.set(StatsCategoryView.sun.rawValue, forKey: SettingsKeys.statsCategoryView)

        let stored = temporary.defaults.string(forKey: SettingsKeys.statsCategoryView).flatMap(StatsCategoryView.init(rawValue:))
        #expect(stored == .sun)
        #expect(temporary.defaults.string(forKey: SettingsKeys.homeOverviewStyle).flatMap(HomeOverviewStyle.init(rawValue:)) == nil)
    }
}
