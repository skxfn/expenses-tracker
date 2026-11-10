import Foundation
import SwiftData

/// Чем закончилась попытка автокопии.
public enum AutoBackupOutcome: Equatable, Sendable {
    /// Копия записана: отпечаток данных и дата копии — чтобы следующая не повторяла ту же и узнавала свой файл.
    case written(fingerprint: String, exportedAt: Date)
    case skipped(AutoBackupDecision)
}

/// Автокопия вне главного потока: свой контекст SwiftData читает сохранённые данные, кодирует их в формат
/// резервной копии и пишет в папку. Один экземпляр — одна попытка (свежий контекст без кэша прошлых выборок).
@ModelActor
public actor AutoBackupWriter {
    public func backUp(
        to folder: AutoBackupFolder,
        currencyCode: String,
        lastFingerprint: String?,
        trigger: AutoBackupTrigger,
        now: Date = .now,
        timeZone: TimeZone = .current,
        keeping count: Int = AutoBackupFiles.dailyCopiesToKeep
    ) throws(AutoBackupError) -> AutoBackupOutcome {
        // Недоступная папка не стоит выборки всей базы.
        try folder.checkAvailability()
        let payload: BackupPayload
        let fingerprint: String
        do {
            payload = try BackupExporter.makePayload(from: modelContext, currencyCode: currencyCode, exportedAt: now)
            fingerprint = try payload.contentFingerprint()
        } catch {
            throw .writeFailed
        }

        let decision = AutoBackupPolicy.decision(
            trigger: trigger,
            fingerprint: fingerprint,
            lastFingerprint: lastFingerprint,
            expenseCount: payload.expenses.count
        )
        guard decision == .write else { return .skipped(decision) }

        let data: Data
        do {
            data = try BackupFormat.makeEncoder().encode(payload)
        } catch {
            throw .writeFailed
        }
        try folder.write(data, at: now, timeZone: timeZone, keeping: count)
        return .written(fingerprint: fingerprint, exportedAt: payload.exportedAt)
    }
}
