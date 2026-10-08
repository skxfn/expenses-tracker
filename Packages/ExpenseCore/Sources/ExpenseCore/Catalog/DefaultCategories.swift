/// Шаблон категории без привязки к хранилищу.
public struct CategoryTemplate: Hashable, Sendable {
    public let name: String
    public let iconName: String
    public let colorHex: String
}

/// Базовые категории, которые создаются при первом запуске.
public enum DefaultCategories {
    public static let all: [CategoryTemplate] = [
        CategoryTemplate(name: "Продукты", iconName: "cart.fill", colorHex: "#2E9D63"),
        CategoryTemplate(name: "Кафе и рестораны", iconName: "fork.knife", colorHex: "#DD6B20"),
        CategoryTemplate(name: "Транспорт", iconName: "bus.fill", colorHex: "#3E7BE6"),
        CategoryTemplate(name: "Жильё и ЖКХ", iconName: "house.fill", colorHex: "#A0674B"),
        CategoryTemplate(name: "Связь и интернет", iconName: "wifi", colorHex: "#0B93B8"),
        CategoryTemplate(name: "Здоровье", iconName: "cross.case.fill", colorHex: "#E5484D"),
        CategoryTemplate(name: "Развлечения", iconName: "theatermasks.fill", colorHex: "#8E4EC6"),
        CategoryTemplate(name: "Одежда", iconName: "tshirt.fill", colorHex: "#D6409F"),
        CategoryTemplate(name: "Подписки", iconName: "repeat.circle.fill", colorHex: "#5B5BD6"),
        CategoryTemplate(name: "Подарки", iconName: "gift.fill", colorHex: "#C2185B"),
        CategoryTemplate(name: "Образование", iconName: "graduationcap.fill", colorHex: "#B8860B"),
        CategoryTemplate(name: "Другое", iconName: "ellipsis.circle.fill", colorHex: "#8B8D98")
    ]
}
