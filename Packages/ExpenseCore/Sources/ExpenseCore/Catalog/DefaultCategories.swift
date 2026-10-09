/// Шаблон категории без привязки к хранилищу.
public struct CategoryTemplate: Hashable, Sendable {
    public let name: String
    /// Имя иконки MingCute.
    public let iconName: String
    public let tone: GouacheTone

    /// Цвет в данных — основной hex тона.
    public var colorHex: String { tone.mainHex }
}

/// Базовые категории, которые создаются при первом запуске (`design/migration.json` → `defaultCategories`).
public enum DefaultCategories {
    public static let all: [CategoryTemplate] = [
        CategoryTemplate(name: "Продукты", iconName: "basket-fill", tone: .shalfey),
        CategoryTemplate(name: "Кафе", iconName: "fork-knife-fill", tone: .abrikos),
        CategoryTemplate(name: "Транспорт", iconName: "bus-fill", tone: .kobalt),
        CategoryTemplate(name: "Дом", iconName: "home-4-fill", tone: .umbra),
        CategoryTemplate(name: "Связь", iconName: "wifi-fill", tone: .tseruleum),
        CategoryTemplate(name: "Здоровье", iconName: "capsule-fill", tone: .kinovar),
        CategoryTemplate(name: "Развлечения", iconName: "celebrate-fill", tone: .ametist),
        CategoryTemplate(name: "Одежда", iconName: "t-shirt-fill", tone: .pion),
        CategoryTemplate(name: "Подписки", iconName: "repeat-fill", tone: .ultramarin),
        CategoryTemplate(name: "Подарки", iconName: "gift-fill", tone: .krapplak),
        CategoryTemplate(name: "Образование", iconName: "mortarboard-fill", tone: .okhra),
        CategoryTemplate(name: "Другое", iconName: "more-3-fill", tone: .grafit)
    ]
}
