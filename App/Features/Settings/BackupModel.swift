import Foundation
import Observation
import SwiftData
import ExpenseCore

/// Сохранение и восстановление резервной копии: подготовка файла, чтение, состояние диалогов, ошибки.
@Observable
final class BackupModel {
    /// `Double` (секунды с 1970) — дата последнего сохранения копии, для `@AppStorage`.
    static let lastExportDateKey = "lastBackupExportDate"

    var isExporterPresented = false
    var isImporterPresented = false
    var importSession: ImportSession?
    var alert: FailureAlert?
    /// Тост «Копия сохранена» после системного окна сохранения.
    var isExportDoneToastShown = false
    private(set) var exportDocument: BackupDocument?
    private(set) var exportFileName = ""
    /// Идёт подготовка копии или чтение файла: строка показывает индикатор, обе кнопки не нажимаются.
    private(set) var isPreparingExport = false
    private(set) var isReadingImport = false

    var isBusy: Bool { isPreparingExport || isReadingImport }

    func prepareExport(context: ModelContext, currencyCode: String) async {
        guard !isBusy else { return }
        isPreparingExport = true
        defer { isPreparingExport = false }
        await Self.letProgressAppear()
        do {
            exportDocument = BackupDocument(data: try BackupExporter.exportData(from: context, currencyCode: currencyCode))
            exportFileName = Self.exporterFileName(BackupExporter.defaultFileName())
            isExporterPresented = true
        } catch {
            alert = .exportPrepare
        }
    }

    /// `true` — файл сохранён.
    func finishExport(_ result: Result<URL, any Error>) -> Bool {
        exportDocument = nil
        switch result {
        case .success:
            isExportDoneToastShown = true
            return true
        case .failure:
            alert = .exportSave
            return false
        }
    }

    func cancelExport() {
        exportDocument = nil
    }

    /// Читает и проверяет выбранный файл. Хранилище не меняется до выбора режима восстановления.
    func openImportedFile(_ result: Result<URL, any Error>) async {
        guard !isBusy else { return }
        isReadingImport = true
        defer { isReadingImport = false }
        await Self.letProgressAppear()
        do {
            let data = try BackupDocument(contentsOf: try result.get()).data
            importSession = ImportSession(payload: try BackupImporter.decode(data))
        } catch {
            alert = .backupRead(error)
        }
    }

    /// `.fileExporter` сам ставит расширение по типу содержимого: без расширения дописывает `.json`,
    /// с `.json` — не дублирует (проверено на Mac Catalyst, где та же UIKit-реализация SwiftUI).
    /// Расширение убираем, чтобы `….json.json` не получилось ни при каком из этих вариантов.
    static func exporterFileName(_ fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// Копия собирается и разбирается на главном потоке (контекст SwiftData) и на большой базе занимает секунды.
    /// Пауза перед работой даёт кадру с индикатором отрисоваться до того, как поток занят.
    static func letProgressAppear() async {
        try? await Task.sleep(for: .milliseconds(50))
    }
}

/// Одно восстановление: файл уже прочитан, ждём выбора режима, затем показываем отчёт.
@Observable
final class ImportSession: Identifiable {
    let id = UUID()
    let payload: BackupPayload
    private(set) var report: ImportReport?
    private(set) var isCurrencyQuestionAnswered = false
    /// Режим, который сейчас применяется: его кнопка показывает индикатор, обе не нажимаются.
    private(set) var applyingMode: ImportMode?
    var alert: FailureAlert?

    init(payload: BackupPayload) {
        self.payload = payload
    }

    func apply(_ mode: ImportMode, context: ModelContext) async {
        guard applyingMode == nil else { return }
        applyingMode = mode
        defer { applyingMode = nil }
        await BackupModel.letProgressAppear()
        do {
            report = try BackupImporter.apply(payload, to: context, mode: mode)
        } catch {
            alert = .backupApply(error)
        }
    }

    /// После восстановления спрашиваем про валюту, только если в файле другая и она известна системе.
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
