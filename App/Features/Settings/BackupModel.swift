import Foundation
import Observation
import SwiftData
import ExpenseCore

/// Экспорт и импорт резервной копии: подготовка файла, чтение, состояние диалогов.
@Observable
final class BackupModel {
    /// `Double` (секунды с 1970) — дата последнего успешного экспорта, для `@AppStorage`.
    static let lastExportDateKey = "lastBackupExportDate"

    var isExporterPresented = false
    var isImporterPresented = false
    var importSession: ImportSession?
    var errorMessage: String?
    private(set) var exportDocument: BackupDocument?
    private(set) var exportFileName = ""

    func prepareExport(context: ModelContext, currencyCode: String) {
        do {
            exportDocument = BackupDocument(data: try BackupExporter.exportData(from: context, currencyCode: currencyCode))
            exportFileName = Self.exporterFileName(BackupExporter.defaultFileName())
            isExporterPresented = true
        } catch {
            errorMessage = "Не удалось подготовить резервную копию: \(error.localizedDescription)"
        }
    }

    /// `true` — файл сохранён.
    func finishExport(_ result: Result<URL, any Error>) -> Bool {
        exportDocument = nil
        switch result {
        case .success:
            return true
        case .failure(let error):
            errorMessage = "Не удалось сохранить файл: \(error.localizedDescription)"
            return false
        }
    }

    func cancelExport() {
        exportDocument = nil
    }

    /// Читает и проверяет выбранный файл. Хранилище не меняется до выбора режима импорта.
    func openImportedFile(_ result: Result<URL, any Error>) {
        do {
            let data = try BackupDocument(contentsOf: try result.get()).data
            importSession = ImportSession(payload: try BackupImporter.decode(data))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `.fileExporter` сам ставит расширение по типу содержимого: без расширения дописывает `.json`,
    /// с `.json` — не дублирует (проверено на Mac Catalyst, где та же UIKit-реализация SwiftUI).
    /// Расширение убираем, чтобы `….json.json` не получилось ни при каком из этих вариантов.
    static func exporterFileName(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }
}

/// Один импорт: файл уже прочитан, ждём выбора режима, затем показываем отчёт.
@Observable
final class ImportSession: Identifiable {
    let id = UUID()
    let payload: BackupPayload
    private(set) var report: ImportReport?
    private(set) var isCurrencyQuestionAnswered = false
    var errorMessage: String?

    init(payload: BackupPayload) {
        self.payload = payload
    }

    func apply(_ mode: ImportMode, context: ModelContext) {
        do {
            report = try BackupImporter.apply(payload, to: context, mode: mode)
        } catch {
            errorMessage = "Импорт не выполнен, данные не изменились. \(error.localizedDescription)"
        }
    }

    /// После импорта спрашиваем про валюту, только если в файле другая и она известна системе.
    func needsCurrencyDecision(currentCode: String) -> Bool {
        report != nil
            && !isCurrencyQuestionAnswered
            && payload.currencyCode != currentCode
            && Locale.commonISOCurrencyCodes.contains(payload.currencyCode)
    }

    func answerCurrencyQuestion() {
        isCurrencyQuestionAnswered = true
    }
}
