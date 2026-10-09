/// Иконка категории из набора MingCute Fill.
public struct CategoryIcon: Identifiable, Hashable, Sendable {
    /// Имя MingCute — оно же имя ассета в `Assets.xcassets/Categories/` и значение `iconName` в данных.
    public let name: String
    /// id строки VoiceOver в `design/copy.json`: `cat.icon.name.<группа>.<номер>`.
    public let accessibilityKey: String

    public var id: String { name }
}

/// Группа иконок для выбора.
public struct CategoryIconGroup: Identifiable, Hashable, Sendable {
    /// id подзаголовка в `design/copy.json`: `cat.icon.group.<номер>` (строка `cat.icon.groups`).
    public let titleKey: String
    public let icons: [CategoryIcon]

    public var id: String { titleKey }
}

/// Иконки категорий: 9 групп макета «Новая подкатегория» (по 6, в первой 12).
/// В конце групп — иконки, которых в макете нет, но которые нужны данным прошлой версии
/// (`design/migration.json` → `icons`); строк VoiceOver для них в `copy.json` пока нет.
public enum CategoryIconCatalog {
    public static let groups: [CategoryIconGroup] = [
        group(1, [
            "basket-fill", "shopping-cart-1-fill", "shopping-bag-1-fill", "shop-fill", "bread-fill",
            "apple-fruit-fill", "fork-knife-fill", "teacup-fill", "pizza-fill", "fries-fill",
            "ice-cream-fill", "wineglass-fill"
        ]),
        group(2, [
            "bus-fill", "car-fill", "train-fill", "gas-station-fill", "airplane-fill", "suitcase-fill",
            "bike-fill", "parking-fill"
        ]),
        group(3, [
            "home-4-fill", "sofa-fill", "bulb-fill", "drop-fill", "flame-fill", "tool-fill",
            "wash-machine-fill"
        ]),
        group(4, [
            "wifi-fill", "cellphone-fill", "laptop-fill", "headphone-fill", "tv-1-fill", "camera-fill",
            "signal-fill"
        ]),
        group(5, [
            "capsule-fill", "first-aid-kit-fill", "dental-fill", "heartbeat-fill", "barbell-fill", "run-fill",
            "heart-fill", "stethoscope-fill", "leaf-fill"
        ]),
        group(6, [
            "celebrate-fill", "ticket-fill", "movie-fill", "music-fill", "game-2-fill", "book-2-fill",
            "palette-fill", "umbrella-2-fill"
        ]),
        group(7, [
            "t-shirt-fill", "dress-fill", "shoe-fill", "lipstick-fill", "scissors-fill", "parfum-fill",
            "eyeglass-fill", "hair-fill", "sparkles-fill"
        ]),
        group(8, [
            "gift-fill", "cake-fill", "baby-carriage-fill", "paw-fill", "mortarboard-fill", "hand-heart-fill",
            "group-fill", "bear-fill"
        ]),
        group(9, [
            "repeat-fill", "bank-card-fill", "bank-fill", "pig-money-fill", "bill-fill", "more-3-fill",
            "cash-fill", "briefcase-fill", "tag-fill"
        ])
    ]

    /// Все имена подряд, в порядке групп.
    public static let allNames: [String] = groups.flatMap { $0.icons.map(\.name) }

    /// Иконка из каталога (значит, у неё есть ассет).
    public static func contains(_ name: String) -> Bool {
        nameSet.contains(name)
    }

    private static let nameSet = Set(allNames)

    private static func group(_ number: Int, _ names: [String]) -> CategoryIconGroup {
        CategoryIconGroup(
            titleKey: "cat.icon.group.\(number)",
            icons: names.enumerated().map { index, name in
                CategoryIcon(name: name, accessibilityKey: "cat.icon.name.\(number).\(index + 1)")
            }
        )
    }
}
