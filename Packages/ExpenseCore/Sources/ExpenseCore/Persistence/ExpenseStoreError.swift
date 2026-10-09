import Foundation

/// Ошибки валидации `ExpenseStore`. Тексты — запасные: в интерфейсе App подбирает строку
/// `design/copy.json` по случаю перечисления.
public enum ExpenseStoreError: LocalizedError, Equatable {
    case invalidAmount
    case emptyCategoryName
    case duplicateCategoryName(String)
    case invalidColorHex(String)
    case invalidReassignTarget
    /// Активных категорий верхнего уровня уже `ExpenseStore.topLevelCategoryLimit` (`cat.group.limit`).
    case categoryLimitReached
    /// Родитель — сама категория или подкатегория: глубина только один уровень.
    case invalidParent
    /// Категорию с подкатегориями нельзя сделать подкатегорией (`cat.typeSwitch.block`).
    case hasSubcategories

    public var errorDescription: String? {
        switch self {
        case .invalidAmount:
            "Сумма должна быть больше нуля."
        case .emptyCategoryName:
            "Введите название категории."
        case .duplicateCategoryName(let name):
            "Категория «\(name)» уже есть."
        case .invalidColorHex(let hex):
            "Некорректный цвет категории: \(hex)."
        case .invalidReassignTarget:
            "Нельзя перенести расходы в удаляемую категорию."
        case .categoryLimitReached:
            "Категорий уже 15\u{00A0}— это предел. Новую можно добавить подкатегорией."
        case .invalidParent:
            "Подкатегорию нельзя вложить в подкатегорию."
        case .hasSubcategories:
            "Категорию с подкатегориями нельзя сделать подкатегорией."
        }
    }
}
