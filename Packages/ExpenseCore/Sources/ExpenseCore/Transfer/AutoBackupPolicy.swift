import CryptoKit
import Foundation

/// Кто просит копию: само приложение после изменений или пользователь кнопкой «Сохранить сейчас».
public enum AutoBackupTrigger: Sendable {
    case automatic
    case manual
}

/// Писать ли автокопию.
public enum AutoBackupDecision: Equatable, Sendable {
    case write
    /// Данные не менялись с прошлой копии: тот же файл не пишем, дневная копия без изменений не нужна.
    case skipUnchanged
    /// Трат нет: пустая база не перезаписывает копию сама (сбой хранилища, переустановка) — только по кнопке.
    case skipNoExpenses
}

public enum AutoBackupPolicy {
    /// Ручная копия пишется всегда; автоматическая — только при изменившихся данных и непустой базе.
    public static func decision(
        trigger: AutoBackupTrigger,
        fingerprint: String,
        lastFingerprint: String?,
        expenseCount: Int
    ) -> AutoBackupDecision {
        guard trigger == .automatic else { return .write }
        guard expenseCount > 0 else { return .skipNoExpenses }
        return fingerprint == lastFingerprint ? .skipUnchanged : .write
    }

    /// Копия в папке известна приложению: её записало оно само или из неё восстанавливали данные.
    /// Чужую копию (другой iPhone, прошлая установка) автокопия без вопроса не перезаписывает.
    public static func isKnownCopy(exportedAt: Date, knownExportDates: [Date]) -> Bool {
        let normalized = BackupFormat.normalized(exportedAt)
        return knownExportDates.contains { BackupFormat.normalized($0) == normalized }
    }
}

extension BackupPayload {
    /// Отпечаток данных копии (SHA-256 в hex) без даты создания: одинаковые данные — одинаковый отпечаток.
    public func contentFingerprint() throws -> String {
        var content = self
        content.exportedAt = Date(timeIntervalSince1970: 0)
        let digest = SHA256.hash(data: try BackupFormat.makeEncoder().encode(content))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
