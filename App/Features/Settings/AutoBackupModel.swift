import Foundation
import Observation
import SwiftData
import UIKit
import ExpenseCore

/// Автокопия в облако: копия сама пишется в папку, выбранную в «Файлах» (iCloud Drive, другой провайдер),
/// после изменений данных (с задержкой) и при уходе приложения в фон. Облако синхронизирует провайдер файлов —
/// без iCloud entitlements, которых у бесплатного Apple ID нет.
///
/// Папка хранится закладкой в UserDefaults и переживает перезапуск; удаление приложения стирает только закладку,
/// файлы в облаке остаются. Запись — `AutoBackupWriter` вне главного потока, формат — обычная резервная копия.
/// Копию из чужой установки (другой iPhone, до переустановки) без решения пользователя не перезаписываем.
@Observable
final class AutoBackupModel {
    enum Problem: String {
        /// Папку удалили, переместили или доступ потерян — выбрать заново.
        case folderUnavailable
        /// Запись не удалась по другой причине — «Сохранить сейчас» повторит.
        case writeFailed
    }

    /// Выбранная папка уже содержит «последнюю» копию, которую приложение не знает: ждём решения.
    struct FolderCandidate: Identifiable {
        let id = UUID()
        let bookmark: Data
        let url: URL
        let displayName: String
        let existing: AutoBackupExistingCopy
    }

    /// Ключи UserDefaults.
    enum Keys {
        static let isEnabled = "autoBackup.isEnabled"
        /// `Data` — закладка на папку (`AutoBackupFolder.bookmark(for:)`).
        static let bookmark = "autoBackup.bookmark"
        static let folderName = "autoBackup.folderName"
        /// `Double` (секунды с 1970) — когда записана последняя копия.
        static let lastBackupDate = "autoBackup.lastBackupDate"
        /// `String` — отпечаток данных последней записанной копии (`BackupPayload.contentFingerprint`).
        static let lastFingerprint = "autoBackup.lastFingerprint"
        /// `Double` — `exportedAt` последней записанной копии: по нему приложение узнаёт свой файл в папке.
        static let lastExportedAt = "autoBackup.lastExportedAt"
        /// `Double` — `exportedAt` копии, из которой последний раз восстанавливали данные: эту копию тоже знаем.
        static let restoredExportedAt = "autoBackup.restoredExportedAt"
        /// `Bool` — есть изменения, которые ещё не попали в копию (переживает выгрузку приложения).
        static let hasPendingChanges = "autoBackup.hasPendingChanges"
        static let problem = "autoBackup.problem"
    }

    /// Пауза после изменения: подряд записанные траты дают одну копию, а не по копии на каждую.
    static let debounce: Duration = .seconds(5)

    private(set) var isEnabled: Bool
    private(set) var folderName: String?
    private(set) var folderURL: URL?
    private(set) var lastBackupDate: Date?
    private(set) var problem: Problem?
    private(set) var isWriting = false
    var isFolderPickerPresented = false
    var candidate: FolderCandidate?
    var alert: FailureAlert?

    private let defaults: UserDefaults
    private var debounceTask: Task<Void, Never>?
    /// Попытки идут по очереди: следующая видит отпечаток, записанный предыдущей.
    private var lastRun: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Папка, из копии которой сейчас восстанавливают данные; после восстановления она станет папкой автокопии.
    private var restoringCandidate: (candidate: FolderCandidate, session: ImportSession)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        folderName = defaults.string(forKey: Keys.folderName)
        let timestamp = defaults.double(forKey: Keys.lastBackupDate)
        lastBackupDate = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        problem = defaults.string(forKey: Keys.problem).flatMap(Problem.init(rawValue:))
        folderURL = defaults.data(forKey: Keys.bookmark).flatMap { try? AutoBackupFolder.resolve(bookmark: $0).folder.url }
    }

    var hasFolder: Bool { folderName != nil }

    /// Переключатель показывает «вкл», пока открыт выбор папки после включения.
    var isToggleOn: Bool { isEnabled || isFolderPickerPresented }

    // MARK: - Жизненный цикл

    /// Данные сохранены: копия — через `debounce`, если за это время не будет новых изменений.
    func dataDidChange(container: ModelContainer) {
        guard isEnabled else { return }
        defaults.set(true, forKey: Keys.hasPendingChanges)
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await enqueue(.automatic, container: container).value
        }
    }

    /// Запуск: изменения, не попавшие в копию (приложение выгрузили до записи), — в копию.
    func resumePendingBackup(container: ModelContainer) {
        guard isEnabled, defaults.bool(forKey: Keys.hasPendingChanges) else { return }
        dataDidChange(container: container)
    }

    /// Уход в фон: несохранённое в копию пишем сразу, под фоновой задачей — иначе система приостановит запись.
    func sceneDidEnterBackground(container: ModelContainer) {
        guard isEnabled, defaults.bool(forKey: Keys.hasPendingChanges) else { return }
        debounceTask?.cancel()
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "AutoBackup") { [weak self] in
            self?.endBackgroundTask()
        }
        let run = enqueue(.automatic, container: container)
        Task {
            await run.value
            endBackgroundTask()
        }
    }

    // MARK: - Действия пользователя

    func setEnabled(_ isOn: Bool, container: ModelContainer) {
        guard isOn else {
            isEnabled = false
            defaults.set(false, forKey: Keys.isEnabled)
            debounceTask?.cancel()
            return
        }
        guard hasFolder, problem != .folderUnavailable else {
            isFolderPickerPresented = true
            return
        }
        isEnabled = true
        defaults.set(true, forKey: Keys.isEnabled)
        saveNow(container: container)
    }

    func saveNow(container: ModelContainer) {
        debounceTask?.cancel()
        enqueue(.manual, container: container)
    }

    /// Папка из окна выбора. Пустую или со своей копией принимаем сразу; с чужой — спрашиваем (`candidate`).
    func folderPicked(_ result: Result<URL, any Error>, container: ModelContainer) async {
        guard case .success(let url) = result else { return }
        let bookmark: Data
        do {
            bookmark = try AutoBackupFolder.bookmark(for: url)
        } catch {
            alert = .autoBackupPick
            return
        }
        isWriting = true
        let folder = AutoBackupFolder(url: url)
        let existing = await Task.detached { try? folder.latestCopy() }.value
        isWriting = false
        guard let existing else {
            alert = .autoBackupPick
            return
        }
        let candidate = FolderCandidate(bookmark: bookmark, url: url, displayName: folder.displayName, existing: existing)
        if case .readable(let payload) = existing, !isKnownCopy(payload) {
            self.candidate = candidate
        } else if case .unreadable = existing {
            self.candidate = candidate
        } else {
            adopt(candidate, container: container)
        }
    }

    /// «Заменить копию»: текущие данные — поверх чужой копии.
    func replaceCopy(of candidate: FolderCandidate, container: ModelContainer) {
        self.candidate = nil
        adopt(candidate, container: container)
    }

    /// «Восстановить из копии»: сессия для `ImportView`; папка станет папкой автокопии, только если данные восстановят.
    func restore(from candidate: FolderCandidate) -> ImportSession? {
        guard case .readable(let payload) = candidate.existing else { return nil }
        self.candidate = nil
        let session = ImportSession(payload: payload)
        restoringCandidate = (candidate, session)
        return session
    }

    /// Окно восстановления закрыто: восстановили — папка принята и в неё пишется копия; закрыли без этого — ничего.
    func restoreSheetDismissed(container: ModelContainer) {
        guard let restoring = restoringCandidate else { return }
        restoringCandidate = nil
        if restoring.session.report != nil {
            adopt(restoring.candidate, container: container)
        }
    }

    /// Восстановили данные из копии (любой): эту копию в папке перезаписывать можно без вопроса.
    static func recordRestore(of payload: BackupPayload, defaults: UserDefaults = .standard) {
        defaults.set(payload.exportedAt.timeIntervalSince1970, forKey: Keys.restoredExportedAt)
    }

    // MARK: - Запись

    private func adopt(_ candidate: FolderCandidate, container: ModelContainer) {
        defaults.set(candidate.bookmark, forKey: Keys.bookmark)
        defaults.set(candidate.displayName, forKey: Keys.folderName)
        // Новая папка: прошлый отпечаток к ней не относится.
        defaults.removeObject(forKey: Keys.lastFingerprint)
        folderName = candidate.displayName
        folderURL = candidate.url
        setProblem(nil)
        isEnabled = true
        defaults.set(true, forKey: Keys.isEnabled)
        saveNow(container: container)
    }

    @discardableResult
    private func enqueue(_ trigger: AutoBackupTrigger, container: ModelContainer) -> Task<Void, Never> {
        let previous = lastRun
        let run = Task {
            await previous?.value
            await backUp(trigger, container: container)
        }
        lastRun = run
        return run
    }

    private func backUp(_ trigger: AutoBackupTrigger, container: ModelContainer) async {
        guard isEnabled, let bookmark = defaults.data(forKey: Keys.bookmark) else { return }
        isWriting = true
        defer { isWriting = false }

        let folder: AutoBackupFolder
        do {
            let resolved = try AutoBackupFolder.resolve(bookmark: bookmark)
            folder = resolved.folder
            if let refreshed = resolved.refreshedBookmark {
                defaults.set(refreshed, forKey: Keys.bookmark)
            }
            folderURL = folder.url
        } catch {
            setProblem(.folderUnavailable)
            return
        }

        // Снимаем пометку до записи: изменения во время записи поставят её снова.
        defaults.set(false, forKey: Keys.hasPendingChanges)
        do {
            let outcome = try await AutoBackupWriter(modelContainer: container).backUp(
                to: folder,
                currencyCode: CurrencySettings.currencyCode(in: defaults),
                lastFingerprint: defaults.string(forKey: Keys.lastFingerprint),
                trigger: trigger
            )
            if case .written(let fingerprint, let exportedAt) = outcome {
                defaults.set(fingerprint, forKey: Keys.lastFingerprint)
                defaults.set(exportedAt.timeIntervalSince1970, forKey: Keys.lastExportedAt)
                defaults.set(exportedAt.timeIntervalSince1970, forKey: Keys.lastBackupDate)
                lastBackupDate = exportedAt
                setProblem(nil)
            }
        } catch {
            defaults.set(true, forKey: Keys.hasPendingChanges)
            setProblem(error == .folderUnavailable ? .folderUnavailable : .writeFailed)
        }
    }

    private func isKnownCopy(_ payload: BackupPayload) -> Bool {
        let known = [Keys.lastExportedAt, Keys.restoredExportedAt]
            .map { defaults.double(forKey: $0) }
            .filter { $0 > 0 }
            .map { Date(timeIntervalSince1970: $0) }
        return AutoBackupPolicy.isKnownCopy(exportedAt: payload.exportedAt, knownExportDates: known)
    }

    private func setProblem(_ problem: Problem?) {
        self.problem = problem
        defaults.set(problem?.rawValue, forKey: Keys.problem)
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
