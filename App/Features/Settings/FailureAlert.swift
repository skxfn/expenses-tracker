import SwiftUI
import ExpenseCore

/// Алерт ошибки по схеме `copy.json` (§2.2): заголовок «Не удалось …», в теле — что с данными и что делать,
/// кнопка «ОК» кириллицей. Без UUID, путей и номеров формата: системный текст ошибки сюда не попадает.
struct FailureAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    // MARK: Резервная копия

    /// Файл не удалось подготовить к сохранению.
    static var exportPrepare: FailureAlert {
        FailureAlert(
            title: String(localized: "backup.exportPrepareError.title"),
            message: String(localized: "backup.exportPrepareError.message")
        )
    }

    /// Системное окно сохранения вернуло ошибку.
    static var exportSave: FailureAlert {
        FailureAlert(
            title: String(localized: "backup.exportSaveError.title"),
            message: String(localized: "backup.exportSaveError.message")
        )
    }

    /// Файл не прочитался или не прошёл проверку (`BackupImporter.decode`).
    static func backupRead(_ error: any Error) -> FailureAlert {
        FailureAlert(title: String(localized: "error.backup.unreadable"), message: backupReason(error))
    }

    /// Загрузка в хранилище не удалась — данные не изменились (импорт откатывается целиком).
    static func backupApply(_ error: any Error) -> FailureAlert {
        let reason = error is BackupError ? backupReason(error) : ""
        let message = L10n.format("backup.importApplyError.message", reason)
        return FailureAlert(
            title: String(localized: "backup.importApplyError.title"),
            message: message.trimmingCharacters(in: .whitespaces)
        )
    }

    /// Причина по `BackupError` (`error.backup.*`). Ошибка чтения файла системой — как битый файл.
    private static func backupReason(_ error: any Error) -> String {
        guard let error = error as? BackupError else {
            return String(localized: "error.backup.detail.notJSON")
        }
        let key: String = switch error {
        case .unreadableFile(let reason): "error.backup.detail.\(reason.rawValue)"
        case .newerFormat: "error.backup.newerFormat"
        case .unsupportedFormat: "error.backup.unsupportedFormat"
        case .duplicateCategoryID: "error.backup.duplicateCategory"
        case .duplicateExpenseID: "error.backup.duplicateExpense"
        case .nonPositiveAmount: "error.backup.nonPositiveAmount"
        // В Core тот же текст, что у неверного значения.
        case .invalidParent: "error.backup.detail.badValue"
        }
        return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    // MARK: Перенос из Monefy

    /// Файл Monefy не прочитался (`MonefyCSV.parse`): причина — `error.monefy.*`, у строки — с её номером.
    static func monefyRead(_ error: any Error) -> FailureAlert {
        let message = switch error as? MonefyCSVError {
        case .badRow(let line, let problem): L10n.format("error.monefy.row.\(problem.rawValue)", line)
        case .noExpenses: String(localized: "error.monefy.noExpenses")
        case .notMonefyFile, nil: String(localized: "error.monefy.notMonefy")
        }
        return FailureAlert(title: String(localized: "error.monefy.title"), message: message)
    }

    /// Импорт не записался — данные не изменились (запись откатывается целиком).
    static var monefyApply: FailureAlert {
        FailureAlert(
            title: String(localized: "monefy.importError.title"),
            message: String(localized: "monefy.importError.message")
        )
    }

    // MARK: Хранилище

    /// Ошибка записи `ExpenseStore`: заголовок `global.saveError`, текст — по случаю `ExpenseStoreError`
    /// (`error.store.*`, `cat.*`), для прочих — «Ничего не потеряно…».
    static func store(_ error: any Error) -> FailureAlert {
        FailureAlert(
            title: String(localized: "global.saveError.title"),
            message: (error as? ExpenseStoreError).flatMap(storeMessage) ?? String(localized: "global.saveError.message")
        )
    }

    private static func storeMessage(_ error: ExpenseStoreError) -> String? {
        switch error {
        case .invalidAmount: String(localized: "error.store.invalidAmount")
        case .emptyCategoryName: String(localized: "error.store.emptyCategoryName")
        case .duplicateCategoryName(let name): L10n.format("error.store.duplicateCategoryName", name)
        case .invalidColorHex: String(localized: "error.store.invalidColorHex")
        case .invalidReassignTarget: String(localized: "error.store.invalidReassignTarget")
        case .categoryLimitReached: String(localized: "cat.group.limit")
        case .hasSubcategories: String(localized: "cat.typeSwitch.block")
        // Своего текста нет: UI не даёт выбрать такого родителя.
        case .invalidParent: nil
        }
    }
}

extension View {
    /// Системный алерт ошибки с единственной кнопкой «ОК». Закрытие сбрасывает `alert` в `nil`.
    func failureAlert(_ alert: Binding<FailureAlert?>) -> some View {
        self.alert(
            alert.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { alert.wrappedValue != nil },
                set: { if !$0 { alert.wrappedValue = nil } }
            ),
            presenting: alert.wrappedValue
        ) { _ in
            Button("error.alert.ok", role: .cancel) {}
        } message: { content in
            Text(verbatim: content.message)
        }
    }
}
