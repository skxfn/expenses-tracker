import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

/// Перевод названий базовых категорий (`DefaultCategoryTranslation`, `ExpenseStore.translateDefaultCategories`)
/// и выбор языка в настройках приложения (`LanguagePreference`).
@MainActor
struct DefaultCategoryTranslationTests {
    let container: ModelContainer
    let context: ModelContext
    let store: ExpenseStore
    /// Названия из `design/copy.json` и `design/copy.en.json` (`default.group.N`) — те же, что в каталоге строк App.
    let russian: [String]
    let english: [String]
    let translation: DefaultCategoryTranslation

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        context = ModelContext(container)
        store = ExpenseStore(context: context)
        russian = try Self.defaultNames(in: "design/copy.json")
        english = try Self.defaultNames(in: "design/copy.en.json")
        translation = DefaultCategoryTranslation(names: ["ru": russian, "en": english])
    }

    private static func defaultNames(in path: String) throws -> [String] {
        let copy = try #require(try RepositoryFiles.json(path) as? [String: Any])
        let screens = try #require(copy["screens"] as? [[String: Any]])
        let finals = Dictionary(
            screens.flatMap { ($0["items"] as? [[String: Any]]) ?? [] }
                .compactMap { item in (item["id"] as? String).map { ($0, item["final"] as? String ?? "") } },
            uniquingKeysWith: { first, _ in first }
        )
        return try DefaultCategories.all.indices.map { try #require(finals["default.group.\($0 + 1)"]) }
    }

    private func seed(_ names: [String]) throws -> UserDefaults {
        let temporary = try TemporaryDefaults()
        try store.seedDefaultCategoriesIfNeeded(defaults: temporary.defaults, names: names)
        return temporary.defaults
    }

    private func topLevelNames() throws -> [String] {
        try store.topLevelCategories(includingArchived: true).map(\.name)
    }

    // MARK: - Данные

    @Test func presetsComeFromCopyAndDiffer() {
        #expect(russian == DefaultCategories.all.map(\.name))
        #expect(english.count == russian.count)
        #expect(Set(english).isDisjoint(with: russian))
        #expect(Set(english.map { $0.lowercased() }).count == english.count)
    }

    // MARK: - Перевод

    @Test func translatesUnrenamedCategoriesOnly() throws {
        _ = try seed(english)
        let categories = try store.topLevelCategories()
        // Переименованная пользователем базовая и своя категория с подкатегорией.
        try store.updateCategory(categories[1], name: "Coffee Shops", iconName: categories[1].iconName, colorHex: categories[1].colorHex)
        let own = try store.addCategory(name: "Pets", iconName: "paw-fill", colorHex: GouacheTone.olivka.mainHex)
        let sub = try store.addSubcategory(name: "Groceries", iconName: "tag-fill", parent: own)
        // Архивная базовая тоже переводится: её траты видны в статистике.
        try store.archiveCategory(categories[11])

        let renamed = try store.translateDefaultCategories(translation, to: "ru")

        var expected = russian
        expected[1] = "Coffee Shops"
        expected.append("Pets")
        #expect(renamed == 11)
        #expect(try topLevelNames() == expected)
        #expect(sub.name == "Groceries")
        #expect(categories[11].isArchived)
    }

    @Test func keepsIconsColorsOrderAndExpenses() throws {
        _ = try seed(russian)
        let categories = try store.topLevelCategories()
        let before = categories.map { ($0.id, $0.iconName, $0.colorHex, $0.sortOrder) }
        let lunch = try store.addSubcategory(name: "Обеды", iconName: "tag-fill", parent: categories[1])
        let expense = try store.addExpense(amountMinor: 1250, date: .now, category: lunch)
        let groceries = try store.addExpense(amountMinor: 500, date: .now, category: categories[0])

        try store.translateDefaultCategories(translation, to: "en")

        let after = try store.topLevelCategories()
        #expect(after.map(\.name) == english)
        #expect(after.map(\.id) == before.map(\.0))
        #expect(after.map(\.iconName) == before.map(\.1))
        #expect(after.map(\.colorHex) == before.map(\.2))
        #expect(after.map(\.sortOrder) == before.map(\.3))
        #expect(lunch.name == "Обеды")
        #expect(lunch.parent?.id == categories[1].id)
        #expect(expense.category?.id == lunch.id)
        #expect(groceries.category?.id == categories[0].id)
        #expect(context.hasChanges == false)
    }

    @Test func secondTranslationChangesNothingAndBackRestores() throws {
        _ = try seed(english)

        #expect(try store.translateDefaultCategories(translation, to: "ru") == 12)
        #expect(try store.translateDefaultCategories(translation, to: "ru") == 0)
        #expect(try topLevelNames() == russian)

        #expect(try store.translateDefaultCategories(translation, to: "en") == 12)
        #expect(try topLevelNames() == english)
    }

    @Test func skipsNameTakenByAnotherCategory() throws {
        _ = try seed(russian)
        // Своя категория с английским названием «Кафе» — «Кафе» остаётся, чтобы не было двух «Dining».
        let removed = try #require(try store.topLevelCategories().last)
        try store.deleteCategory(removed, reassignTo: nil)
        try store.addCategory(name: "dining", iconName: "teacup-fill", colorHex: GouacheTone.grafit.mainHex)

        try store.translateDefaultCategories(translation, to: "en")

        let names = try topLevelNames()
        #expect(names[1] == russian[1])
        #expect(names.last == "dining")
        #expect(names[0] == english[0])
    }

    @Test func statusCountsNamedAndTranslatable() throws {
        _ = try seed(english)
        let categories = try store.topLevelCategories()
        try store.updateCategory(categories[0], name: "Food", iconName: categories[0].iconName, colorHex: categories[0].colorHex)

        let toRussian = try store.defaultCategoryNamesStatus(translation, language: "ru")
        let toEnglish = try store.defaultCategoryNamesStatus(translation, language: "en")
        #expect(toRussian == DefaultCategoryNamesStatus(named: 0, translatable: 11))
        #expect(toEnglish == DefaultCategoryNamesStatus(named: 11, translatable: 0))
        #expect(toEnglish.isCurrent)
        #expect(!toRussian.isCurrent)

        try store.translateDefaultCategories(translation, to: "ru")
        #expect(try store.defaultCategoryNamesStatus(translation, language: "ru").isCurrent)
    }

    @Test func nothingToTranslateWithoutDefaults() throws {
        try store.addCategory(name: "Своя", iconName: "tag-fill", colorHex: GouacheTone.grafit.mainHex)

        let status = try store.defaultCategoryNamesStatus(translation, language: "en")
        #expect(status == DefaultCategoryNamesStatus(named: 0, translatable: 0))
        #expect(!status.isCurrent)
        #expect(try store.translateDefaultCategories(translation, to: "en") == 0)
        #expect(try store.translateDefaultCategories(translation, to: "de") == 0)
        #expect(try topLevelNames() == ["Своя"])
    }

    @Test func renamesArePlannedInOrderWithoutStore() {
        let ids = (0..<3).map { _ in UUID() }
        let entries = [
            DefaultCategoryTranslation.Entry(id: ids[0], name: russian[2]),
            DefaultCategoryTranslation.Entry(id: ids[1], name: "Своя"),
            DefaultCategoryTranslation.Entry(id: ids[2], name: english[4])
        ]

        let renames = translation.renames(of: entries, to: "en")

        #expect(renames == [DefaultCategoryTranslation.Entry(id: ids[0], name: english[2])])
    }

    // MARK: - Язык приложения

    @Test func languagePreferenceRoundTripsThroughAppDomain() throws {
        let temporary = try TemporaryDefaults()
        let read = { LanguagePreference.stored(in: temporary.defaults, domainName: temporary.suiteName) }
        #expect(read() == .system)

        LanguagePreference.russian.save(in: temporary.defaults)
        #expect(temporary.defaults.stringArray(forKey: LanguagePreference.appleLanguagesKey) == ["ru"])
        #expect(read() == .russian)

        LanguagePreference.english.save(in: temporary.defaults)
        #expect(read() == .english)

        LanguagePreference.system.save(in: temporary.defaults)
        #expect(read() == .system)
        #expect(temporary.defaults.persistentDomain(forName: temporary.suiteName)?[LanguagePreference.appleLanguagesKey] == nil)
    }

    @Test func storedLanguageIsReadByLanguageCode() throws {
        let temporary = try TemporaryDefaults()
        temporary.defaults.set(["ru-BY"], forKey: LanguagePreference.appleLanguagesKey)
        #expect(LanguagePreference.stored(in: temporary.defaults, domainName: temporary.suiteName) == .russian)
        temporary.defaults.set(["de"], forKey: LanguagePreference.appleLanguagesKey)
        #expect(LanguagePreference.stored(in: temporary.defaults, domainName: temporary.suiteName) == .system)
    }

    @Test func interfaceLanguageFollowsFirstSupportedLanguage() {
        #expect(LanguagePreference.interfaceLanguageCode(for: ["en-US", "ru-RU"]) == "en")
        #expect(LanguagePreference.interfaceLanguageCode(for: ["ru-BY", "en"]) == "ru")
        #expect(LanguagePreference.interfaceLanguageCode(for: ["de-DE", "en-GB", "ru"]) == "en")
        // Третий язык получает исходный — русский.
        #expect(LanguagePreference.interfaceLanguageCode(for: ["de-DE", "fr"]) == "ru")
        #expect(LanguagePreference.interfaceLanguageCode(for: []) == "ru")
    }

    @Test func languageRawValuesAreStable() {
        #expect(LanguagePreference.allCases.map(\.rawValue) == ["system", "ru", "en"])
    }
}
