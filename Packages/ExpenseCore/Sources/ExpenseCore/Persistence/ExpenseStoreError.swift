import Foundation

/// Ошибки валидации `ExpenseStore`. Тексты показываются пользователю как есть.
public enum ExpenseStoreError: LocalizedError, Equatable {
    case invalidAmount
    case emptyCategoryName
    case duplicateCategoryName(String)
    case invalidColorHex(String)
    case invalidReassignTarget

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
        }
    }
}
