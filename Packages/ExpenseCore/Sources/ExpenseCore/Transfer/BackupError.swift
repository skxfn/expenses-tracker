import Foundation

/// Причины, по которым резервную копию нельзя загрузить.
public enum BackupError: LocalizedError, Equatable, Sendable {
    /// Битый JSON или структура не похожа на резервную копию.
    case unreadableFile(details: String)
    case unsupportedFormatVersion(Int)
    case duplicateCategoryID(UUID)
    case duplicateExpenseID(UUID)
    case nonPositiveAmount(expenseID: UUID)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let details):
            "Не удалось прочитать резервную копию: \(details)."
        case .unsupportedFormatVersion(let version) where version > BackupFormat.currentVersion:
            "Резервная копия создана более новой версией приложения (формат \(version)). Обновите приложение и повторите импорт."
        case .unsupportedFormatVersion(let version):
            "Неподдерживаемая версия формата резервной копии: \(version)."
        case .duplicateCategoryID(let id):
            "Файл повреждён: категория \(id.uuidString) встречается в нём несколько раз."
        case .duplicateExpenseID(let id):
            "Файл повреждён: расход \(id.uuidString) встречается в нём несколько раз."
        case .nonPositiveAmount(let id):
            "Файл повреждён: сумма расхода \(id.uuidString) должна быть больше нуля."
        }
    }
}
