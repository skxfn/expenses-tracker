import ExpenseCore

/// Оформление категории для показа: имя, иконка, цвет.
/// Значение без SwiftData — подходит для списков, статистики и превью.
struct CategoryAppearance: Hashable {
    let name: String
    let iconName: String
    let colorHex: String

    /// Для расходов без категории.
    static let uncategorized = CategoryAppearance(
        name: "Без категории",
        iconName: "questionmark",
        colorHex: "#8B8D98"
    )

    init(name: String, iconName: String, colorHex: String) {
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
    }

    init(_ category: ExpenseCategory?) {
        guard let category else {
            self = .uncategorized
            return
        }
        self.init(name: category.name, iconName: category.iconName, colorHex: category.colorHex)
    }
}
