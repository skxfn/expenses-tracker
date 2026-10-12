import Foundation

/// Перевод названий базовых категорий (`DefaultCategories`) на другой язык интерфейса.
///
/// `names` — названия базовых категорий на каждом языке приложения: код языка → названия в порядке
/// `DefaultCategories.all` (в App — строки `default.group.N` каталога). Категория верхнего уровня, чьё имя
/// дословно совпадает с названием базовой категории на каком-нибудь языке, считается непереименованной
/// и получает название той же базовой категории на целевом языке; остальные не трогаются. Подкатегорий среди
/// базовых нет. Имя не меняется, если на целевом языке оно занято другой категорией верхнего уровня (без учёта
/// регистра, как в проверке `ExpenseStore`). Иконка, цвет, порядок и траты не меняются; повторный перевод
/// ничего не делает.
public struct DefaultCategoryTranslation: Sendable {
    /// Категория верхнего уровня (и архивная) по id и имени; в результате `renames` — новое имя.
    public struct Entry: Hashable, Sendable {
        public let id: UUID
        public let name: String

        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    public let names: [String: [String]]

    public init(names: [String: [String]]) {
        self.names = names
    }

    /// Новые имена для перевода на язык `language`, в порядке `categories`.
    public func renames(of categories: [Entry], to language: String) -> [Entry] {
        guard let target = names[language] else { return [] }
        var current = categories.map(\.name)
        var result: [Entry] = []
        for (offset, category) in categories.enumerated() {
            guard let index = templateIndex(of: category.name), target.indices.contains(index) else { continue }
            let newName = target[index]
            let isTaken = current.indices.contains { $0 != offset && current[$0].caseInsensitiveCompare(newName) == .orderedSame }
            guard newName != category.name, !isTaken else { continue }
            current[offset] = newName
            result.append(Entry(id: category.id, name: newName))
        }
        return result
    }

    /// Сколько категорий уже названы как базовые на языке `language`.
    public func namedCount(of categories: [Entry], in language: String) -> Int {
        guard let target = names[language] else { return 0 }
        return categories.filter { target.contains($0.name) }.count
    }

    /// Номер базовой категории с этим названием на любом языке (языки — по коду, чтобы результат не зависел
    /// от порядка словаря).
    private func templateIndex(of name: String) -> Int? {
        for language in names.keys.sorted() {
            if let index = names[language]?.firstIndex(of: name) { return index }
        }
        return nil
    }
}

/// Базовые категории на одном языке: сколько уже названы на нём и сколько можно перевести на него.
public struct DefaultCategoryNamesStatus: Equatable, Sendable {
    public let named: Int
    public let translatable: Int

    public init(named: Int, translatable: Int) {
        self.named = named
        self.translatable = translatable
    }

    /// Базовые категории уже на этом языке: есть названные на нём и переводить нечего.
    public var isCurrent: Bool { named > 0 && translatable == 0 }
}

extension ExpenseStore {
    /// Состояние базовых категорий для языка `language` (категории верхнего уровня, включая архивные).
    public func defaultCategoryNamesStatus(
        _ translation: DefaultCategoryTranslation,
        language: String
    ) throws -> DefaultCategoryNamesStatus {
        let entries = try topLevelCategories(includingArchived: true).map(DefaultCategoryTranslation.Entry.init)
        return DefaultCategoryNamesStatus(
            named: translation.namedCount(of: entries, in: language),
            translatable: translation.renames(of: entries, to: language).count
        )
    }

    /// Переводит непереименованные базовые категории на язык `language` (правила — `DefaultCategoryTranslation`)
    /// через `updateCategory`: имя проходит ту же проверку, что и при правке. Возвращает число переименованных.
    @discardableResult
    public func translateDefaultCategories(_ translation: DefaultCategoryTranslation, to language: String) throws -> Int {
        let categories = try topLevelCategories(includingArchived: true)
        let renames = translation.renames(of: categories.map(DefaultCategoryTranslation.Entry.init), to: language)
        for rename in renames {
            guard let category = categories.first(where: { $0.id == rename.id }) else { continue }
            try updateCategory(category, name: rename.name, iconName: category.iconName, colorHex: category.colorHex)
        }
        return renames.count
    }
}

private extension DefaultCategoryTranslation.Entry {
    init(_ category: ExpenseCategory) {
        self.init(id: category.id, name: category.name)
    }
}
