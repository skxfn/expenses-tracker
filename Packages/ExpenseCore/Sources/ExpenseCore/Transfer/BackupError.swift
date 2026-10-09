import Foundation

/// Причины, по которым резервную копию нельзя загрузить. Тексты взяты из `design/copy.json`
/// (`error.backup.*`) и не содержат UUID и номеров формата; id в случаях — только для отладки.
public enum BackupError: LocalizedError, Equatable, Sendable {
    /// Почему файл не читается как резервная копия. `rawValue` — окончание id строки
    /// `error.backup.detail.<rawValue>` в `copy.json`.
    public enum UnreadableReason: String, Equatable, Sendable {
        /// Битый файл или не JSON.
        case notJSON
        /// JSON, но не резервная копия «Трат».
        case notBackup
        /// Не хватает поля.
        case missingField
        /// Поле не того типа или с неверным значением.
        case badValue
        /// Неверная дата.
        case badDate
    }

    case unreadableFile(UnreadableReason)
    /// Копия из более новой версии приложения.
    case newerFormat
    /// Версия формата, которую приложение не знает (старше первой).
    case unsupportedFormat
    case duplicateCategoryID(UUID)
    case duplicateExpenseID(UUID)
    case nonPositiveAmount(expenseID: UUID)
    /// Родителя подкатегории нет в файле, он ссылается сам на себя или сам подкатегория.
    case invalidParent(categoryID: UUID)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(.notJSON):
            "Файл повреждён или это не копия «Трат». Выберите другой файл."
        case .unreadableFile(.notBackup):
            "Это не резервная копия «Трат». Выберите другой файл."
        case .unreadableFile(.missingField):
            "Файл повреждён: в нём не хватает данных. Выберите другую копию."
        case .unreadableFile(.badValue), .invalidParent:
            "Файл повреждён: часть данных не читается. Выберите другую копию."
        case .unreadableFile(.badDate):
            "Файл повреждён: в нём неверная дата. Выберите другую копию."
        case .newerFormat:
            "Копия сделана в более новой версии «Трат». Обновите приложение и попробуйте снова."
        case .unsupportedFormat:
            "Эта копия не подходит к текущей версии «Трат». Выберите другой файл."
        case .duplicateCategoryID:
            "Файл повреждён: одна категория записана в нём дважды. Выберите другую копию."
        case .duplicateExpenseID:
            "Файл повреждён: одна трата записана в нём дважды. Выберите другую копию."
        case .nonPositiveAmount:
            "Файл повреждён: в нём есть трата с нулевой суммой. Выберите другую копию."
        }
    }
}
