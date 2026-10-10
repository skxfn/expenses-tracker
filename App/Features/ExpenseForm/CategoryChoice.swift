import Foundation
import Accessibility
import ExpenseCore

/// Снимок категории для шита записи: образец, строка «Категория · Подкатегория», «Все категории».
/// Свойства модели SwiftData копируются сразу (ловушка AGENTS.md); для сохранения нужен только `id`.
struct CategoryChoice: Identifiable, Hashable {
    let id: UUID
    let name: String
    /// Имя категории верхнего уровня; `nil` — это сама категория верхнего уровня.
    let parentName: String?
    let iconName: String
    /// Тон категории верхнего уровня; `nil` — цвет не из «Гуаши».
    let tone: GouacheTone?
    /// Категория верхнего уровня с активными подкатегориями: образец с полосками оттенков,
    /// в VoiceOver — «Продукты, без подкатегории».
    let hasSubcategories: Bool
    /// Сама категория или её родитель в архиве (правка старой траты).
    let isArchived: Bool

    init(_ category: ExpenseCategory) {
        let group = category.parent ?? category
        id = category.id
        name = category.name
        parentName = category.parent?.name
        iconName = category.iconName
        tone = GouacheTone(mainHex: group.colorHex)
        hasSubcategories = category.parent == nil && category.children.contains { !$0.isArchived }
        isArchived = category.isArchived || category.parent?.isArchived == true
    }

    /// Строка под суммой: «Продукты · Супермаркет» или «Кафе».
    var line: String {
        parentName.map { "\($0) · \(name)" } ?? name
    }

    /// VoiceOver: «Супермаркет, Продукты» (`add.swatch.a11y`), «Продукты, без подкатегории»
    /// (`add.swatch.group.a11y`) или имя категории без подкатегорий.
    var accessibilityName: String {
        if let parentName { return "\(name), \(parentName)" }
        return hasSubcategories ? L10n.format("add.swatch.group.a11y", name) : name
    }
}

/// Озвучка в шите записи (copy.json → voiceover).
enum EntrySpeech {
    /// Сумма словом «рубль» (`a11y.money`): «5 рублей», «21,50 рубля».
    static func money(_ minor: Int64, formatter: MoneyFormatter) -> String {
        minor % Money.minorUnitsPerMajor == 0
            ? L10n.format("a11y.money", minor / Money.minorUnitsPerMajor)
            : L10n.format("a11y.money.fraction", formatter.string(fromMinor: minor, style: .plain))
    }

    /// Объявление VoiceOver (сохранено, сумма не введена, лишние знаки).
    static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}
