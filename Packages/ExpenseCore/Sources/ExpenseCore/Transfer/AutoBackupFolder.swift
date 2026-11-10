import Foundation

/// Почему автокопия не записалась.
public enum AutoBackupError: Error, Equatable, Sendable {
    /// Папка удалена, перемещена в корзину или доступ к ней потерян — её нужно выбрать заново.
    case folderUnavailable
    /// Запись не удалась по другой причине (нет места, сбой провайдера файлов) — можно попробовать ещё раз.
    case writeFailed
}

/// «Последняя» копия, которая уже лежит в папке.
public enum AutoBackupExistingCopy: Equatable, Sendable {
    case none
    case readable(BackupPayload)
    /// Файл есть, но не читается этой версией приложения (повреждён или из более новой версии).
    case unreadable
}

/// Папка автокопии, выбранная пользователем в «Файлах» (iCloud Drive, «На iPhone», другой провайдер).
///
/// Доступ к ней даёт security-scoped URL из окна выбора папки; между запусками он хранится закладкой
/// (`bookmark(for:)` → `resolve(bookmark:)`), entitlements для этого не нужны. Каждая операция открывает доступ
/// (`startAccessingSecurityScopedResource`) и работает через `NSFileCoordinator`: так провайдер файлов
/// видит запись и сам отправляет файл в облако — и когда приложение уже закрыто.
public struct AutoBackupFolder: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    // MARK: - Закладка

    /// Закладка на папку из окна выбора: переживает перезапуск приложения.
    public static func bookmark(for url: URL) throws(AutoBackupError) -> Data {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw .folderUnavailable
        }
    }

    /// Папка по закладке. Устаревшую закладку (папку переименовали или перенесли) пересоздаёт —
    /// `refreshedBookmark` нужно сохранить вместо старой.
    public static func resolve(bookmark: Data) throws(AutoBackupError) -> (folder: AutoBackupFolder, refreshedBookmark: Data?) {
        var isStale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
        } catch {
            throw .folderUnavailable
        }
        let refreshed = isStale ? try? Self.bookmark(for: url) : nil
        return (AutoBackupFolder(url: url), refreshed)
    }

    // MARK: - Имя

    /// Имя для строки настроек: «iCloud Drive/Траты»; у других провайдеров — имя папки.
    public var displayName: String {
        let parts = url.standardizedFileURL.pathComponents
        let name: String
        if let index = parts.lastIndex(of: Self.iCloudDriveDirectory) {
            name = ([Self.iCloudDriveName] + parts[(index + 1)...]).joined(separator: "/")
        } else {
            name = withAccess { (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName } ?? url.lastPathComponent
        }
        return name.precomposedStringWithCanonicalMapping
    }

    /// Корень iCloud Drive в файловой системе: `…/Mobile Documents/com~apple~CloudDocs`.
    static let iCloudDriveDirectory = "com~apple~CloudDocs"
    static let iCloudDriveName = "iCloud Drive"

    // MARK: - Чтение

    /// Папка на месте и доступна: проверка до дорогой выборки данных.
    public func checkAvailability() throws(AutoBackupError) {
        try withCheckedAccess { () throws(AutoBackupError) in }
    }

    /// «Последняя» копия папки: перед первой записью — чтобы не затереть копию с другого iPhone или прошлой установки.
    public func latestCopy() throws(AutoBackupError) -> AutoBackupExistingCopy {
        try withCheckedAccess { () throws(AutoBackupError) -> AutoBackupExistingCopy in
            guard fileNames().contains(where: AutoBackupFiles.isLatest) else { return .none }
            let latestURL = url.appending(path: AutoBackupFiles.latestFileName)
            // Файл iCloud Drive может быть выгружен с устройства: координированное чтение его скачивает.
            try? FileManager.default.startDownloadingUbiquitousItem(at: latestURL)
            guard
                let data = try? coordinatedRead(latestURL),
                let payload = try? BackupImporter.decode(data)
            else { return .unreadable }
            return .readable(payload)
        }
    }

    // MARK: - Запись

    /// Пишет копию в дневной файл и в «последнюю», затем удаляет дневные копии старше `count` самых новых дней.
    /// Запись атомарная: прерванная (приложение выгрузили из фона) не оставит полфайла.
    public func write(
        _ data: Data,
        at date: Date,
        timeZone: TimeZone,
        keeping count: Int = AutoBackupFiles.dailyCopiesToKeep
    ) throws(AutoBackupError) {
        try withCheckedAccess { () throws(AutoBackupError) in
            do {
                try coordinatedWrite(data, to: url.appending(path: AutoBackupFiles.dailyFileName(for: date, timeZone: timeZone)))
                try coordinatedWrite(data, to: url.appending(path: AutoBackupFiles.latestFileName))
            } catch {
                throw Self.classify(error)
            }
            removeDailyCopies(AutoBackupFiles.dailyFilesToDelete(among: fileNames(), keeping: count))
        }
    }

    // MARK: - Файлы

    /// Имена файлов папки, с заглушками iCloud; без скачивания выгруженных файлов.
    func fileNames() -> [String] {
        var names: [String] = []
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .immediatelyAvailableMetadataOnly, error: &error) { folder in
            names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        }
        return names
    }

    private func coordinatedRead(_ fileURL: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { target in
            result = Result { try Data(contentsOf: target) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private func coordinatedWrite(_ data: Data, to fileURL: URL) throws {
        var coordinationError: NSError?
        var result: Result<Void, any Error> = .success(())
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinationError) { target in
            result = Result { try data.write(to: target, options: .atomic) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }

    /// Удаление старых копий не должно ронять запись: не удалилось сейчас — удалится в следующий раз.
    /// У выгруженного файла iCloud на диске только заглушка — удаляем то, что есть.
    private func removeDailyCopies(_ names: [String]) {
        for name in names {
            let fileURL = url.appending(path: name)
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forDeleting, error: &error) { target in
                try? FileManager.default.removeItem(at: target)
            }
        }
    }

    // MARK: - Доступ

    private func withAccess<T, Failure: Error>(_ body: () throws(Failure) -> T) throws(Failure) -> T {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }

    /// Доступ к папке и проверка, что она на месте: не удалена и не лежит в корзине.
    /// Удалённую папку не создаём заново — копия ушла бы туда, где её не ждут.
    private func withCheckedAccess<T>(_ body: () throws(AutoBackupError) -> T) throws(AutoBackupError) -> T {
        try withAccess { () throws(AutoBackupError) -> T in
            var isDirectory: ObjCBool = false
            guard
                !isInTrash,
                FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
                isDirectory.boolValue
            else { throw .folderUnavailable }
            return try body()
        }
    }

    /// Закладка на удалённую папку может указать на её место в корзине.
    var isInTrash: Bool {
        url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    /// Нет папки или прав на неё — выбрать папку заново; остальное — попробовать ещё раз.
    static func classify(_ error: any Error) -> AutoBackupError {
        let error = error as NSError
        let unavailableCocoa = [
            NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadNoPermissionError,
            NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError
        ]
        if error.domain == NSCocoaErrorDomain, unavailableCocoa.contains(error.code) { return .folderUnavailable }
        if error.domain == NSPOSIXErrorDomain, [ENOENT, ENOTDIR, EACCES, EPERM, EROFS].contains(Int32(error.code)) {
            return .folderUnavailable
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return classify(underlying) }
        return .writeFailed
    }
}
