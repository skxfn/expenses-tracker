import Foundation
import SwiftData
import Testing
@testable import ExpenseCore

// MARK: - Имена и ротация

@Suite("Автокопия: имена и ротация")
struct AutoBackupFilesTests {
    @Test("Дневная копия — по дню в часовом поясе устройства")
    func dailyFileName() throws {
        let minsk = try #require(TimeZone(identifier: "Europe/Minsk"))
        // 2026-11-10 22:30 UTC — в Минске (+3) уже 11 ноября.
        let date = Date(timeIntervalSince1970: 1_794_349_800)
        #expect(AutoBackupFiles.dailyFileName(for: date, timeZone: minsk) == "Траты-2026-11-11.json")
        #expect(AutoBackupFiles.dailyFileName(for: date, timeZone: .gmt) == "Траты-2026-11-10.json")
    }

    @Test("День дневной копии по имени", arguments: [
        ("Траты-2026-11-10.json", "2026-11-10"),
        (".Траты-2026-11-01.json.icloud", "2026-11-01"),
        ("Траты-последняя.json", nil),
        ("Траты 2026-11-10.json", nil),
        ("Траты-2026-11-10.json.bak", nil),
        ("Траты-2026-13-10.json", nil),
        ("Траты-2026-1-10.json", nil),
        ("Траты-２０２６-11-10.json", nil),
        ("Expenses-2026-11-10.json", nil),
        (".icloud", nil)
    ] as [(String, String?)])
    func day(name: String, expected: String?) {
        #expect(AutoBackupFiles.day(ofDailyFileName: name) == expected)
    }

    @Test("«Последняя» копия узнаётся и по заглушке iCloud")
    func latest() {
        #expect(AutoBackupFiles.isLatest("Траты-последняя.json"))
        #expect(AutoBackupFiles.isLatest(".Траты-последняя.json.icloud"))
        #expect(!AutoBackupFiles.isLatest("Траты-2026-11-10.json"))
    }

    @Test("Ротация: остаются 14 самых новых дней, чужие файлы не трогаются")
    func rotation() {
        let days = (1...20).map { String(format: "Траты-2026-10-%02d.json", $0) }
        let others = ["Траты-последняя.json", "Траты 2026-10-01.json", "заметки.txt", ".DS_Store"]
        let deleted = AutoBackupFiles.dailyFilesToDelete(among: (days + others).shuffled(), keeping: 14)
        #expect(deleted == (1...6).map { String(format: "Траты-2026-10-%02d.json", $0) })
    }

    @Test("Ротация: заглушка iCloud — тот же день, что и файл")
    func rotationPlaceholders() {
        let names = [
            "Траты-2026-10-03.json", ".Траты-2026-10-03.json.icloud",
            ".Траты-2026-10-01.json.icloud", "Траты-2026-10-02.json"
        ]
        #expect(AutoBackupFiles.dailyFilesToDelete(among: names, keeping: 2) == [".Траты-2026-10-01.json.icloud"])
        #expect(AutoBackupFiles.dailyFilesToDelete(among: names, keeping: 3).isEmpty)
        #expect(AutoBackupFiles.dailyFilesToDelete(among: names, keeping: 0).count == names.count)
    }
}

// MARK: - Решение и отпечаток

@MainActor
@Suite("Автокопия: нужна ли копия")
struct AutoBackupPolicyTests {
    @Test("Ручная копия пишется всегда")
    func manual() {
        #expect(AutoBackupPolicy.decision(trigger: .manual, fingerprint: "a", lastFingerprint: "a", expenseCount: 0) == .write)
    }

    @Test("Автоматическая — только при изменениях и с тратами")
    func automatic() {
        #expect(AutoBackupPolicy.decision(trigger: .automatic, fingerprint: "a", lastFingerprint: nil, expenseCount: 1) == .write)
        #expect(AutoBackupPolicy.decision(trigger: .automatic, fingerprint: "b", lastFingerprint: "a", expenseCount: 1) == .write)
        #expect(AutoBackupPolicy.decision(trigger: .automatic, fingerprint: "a", lastFingerprint: "a", expenseCount: 1) == .skipUnchanged)
        #expect(AutoBackupPolicy.decision(trigger: .automatic, fingerprint: "a", lastFingerprint: nil, expenseCount: 0) == .skipNoExpenses)
    }

    @Test("Своя копия узнаётся по дате с точностью до миллисекунды")
    func knownCopy() {
        let date = BackupFixture.exportedAt
        #expect(AutoBackupPolicy.isKnownCopy(exportedAt: BackupFormat.normalized(date), knownExportDates: [date]))
        #expect(!AutoBackupPolicy.isKnownCopy(exportedAt: date.addingTimeInterval(0.002), knownExportDates: [date]))
        #expect(!AutoBackupPolicy.isKnownCopy(exportedAt: date, knownExportDates: []))
    }

    @Test("Отпечаток не зависит от даты копии и меняется с данными")
    func fingerprint() throws {
        let container = try BackupFixture.makeContainer()
        let seed = try BackupFixture.seed(container.mainContext)
        let first = try BackupExporter.makePayload(from: container.mainContext, currencyCode: "BYN", exportedAt: .now)
        let later = try BackupExporter.makePayload(from: container.mainContext, currencyCode: "BYN", exportedAt: .now + 3600)
        #expect(try first.contentFingerprint() == later.contentFingerprint())

        seed.coffee.amountMinor += 1
        try container.mainContext.save()
        let changed = try BackupExporter.makePayload(from: container.mainContext, currencyCode: "BYN", exportedAt: .now)
        #expect(try changed.contentFingerprint() != first.contentFingerprint())

        let otherCurrency = try BackupExporter.makePayload(from: container.mainContext, currencyCode: "USD", exportedAt: .now)
        #expect(try otherCurrency.contentFingerprint() != changed.contentFingerprint())
    }
}

// MARK: - Папка

/// Временная папка; удаляется вместе с объектом.
final class TemporaryFolder {
    let root: URL
    let url: URL

    init(name: String = "Траты") throws {
        root = FileManager.default.temporaryDirectory.appending(path: "AutoBackupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        url = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var fileNames: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []).sorted()
    }

    func create(_ name: String, contents: String = "{}") throws {
        try Data(contents.utf8).write(to: url.appending(path: name))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
@Suite("Автокопия: папка")
struct AutoBackupFolderTests {
    static let date = Date(timeIntervalSince1970: 1_794_315_600) // 2026-11-10 13:00 UTC

    private func backupData(exportedAt: Date = date) throws -> Data {
        let container = try BackupFixture.makeContainer()
        try BackupFixture.seed(container.mainContext)
        return try BackupExporter.exportData(from: container.mainContext, currencyCode: "BYN", exportedAt: exportedAt)
    }

    @Test("Запись: дневной файл и «последняя» с одинаковым содержимым")
    func write() throws {
        let temp = try TemporaryFolder()
        let folder = AutoBackupFolder(url: temp.url)
        let data = try backupData()
        try folder.write(data, at: Self.date, timeZone: .gmt)

        #expect(temp.fileNames == ["Траты-2026-11-10.json", "Траты-последняя.json"])
        #expect(try Data(contentsOf: temp.url.appending(path: "Траты-последняя.json")) == data)
        #expect(try Data(contentsOf: temp.url.appending(path: "Траты-2026-11-10.json")) == data)

        // Тот же день — тот же файл.
        let newer = try backupData(exportedAt: Self.date + 60)
        try folder.write(newer, at: Self.date + 60, timeZone: .gmt)
        #expect(temp.fileNames == ["Траты-2026-11-10.json", "Траты-последняя.json"])
        #expect(try Data(contentsOf: temp.url.appending(path: "Траты-2026-11-10.json")) == newer)
    }

    @Test("Запись удаляет дневные копии старше 14 дней, ручные копии остаются")
    func rotation() throws {
        let temp = try TemporaryFolder()
        for day in 1...20 {
            try temp.create(String(format: "Траты-2026-10-%02d.json", day))
        }
        try temp.create("Траты 2026-10-01.json")
        try AutoBackupFolder(url: temp.url).write(try backupData(), at: Self.date, timeZone: .gmt, keeping: 14)

        let daily = temp.fileNames.filter { AutoBackupFiles.day(ofDailyFileName: $0) != nil }
        #expect(daily.count == 14)
        #expect(daily.first == "Траты-2026-10-08.json")
        #expect(daily.last == "Траты-2026-11-10.json")
        #expect(temp.fileNames.contains("Траты 2026-10-01.json"))
        #expect(temp.fileNames.contains("Траты-последняя.json"))
    }

    @Test("Удалённая папка: ошибка «папка недоступна», заново не создаётся")
    func missingFolder() throws {
        let temp = try TemporaryFolder()
        try FileManager.default.removeItem(at: temp.url)
        let folder = AutoBackupFolder(url: temp.url)

        #expect(throws: AutoBackupError.folderUnavailable) {
            try folder.write(try backupData(), at: Self.date, timeZone: .gmt)
        }
        #expect(throws: AutoBackupError.folderUnavailable) { try folder.latestCopy() }
        #expect(!FileManager.default.fileExists(atPath: temp.url.path(percentEncoded: false)))
    }

    @Test("Папка в корзине — недоступна")
    func trashedFolder() throws {
        let temp = try TemporaryFolder(name: ".Trash/Траты")
        #expect(throws: AutoBackupError.folderUnavailable) {
            try AutoBackupFolder(url: temp.url).write(try backupData(), at: Self.date, timeZone: .gmt)
        }
        #expect(temp.fileNames.isEmpty)
    }

    @Test("«Последняя» копия: нет, читается, не читается")
    func latestCopy() throws {
        let temp = try TemporaryFolder()
        let folder = AutoBackupFolder(url: temp.url)
        #expect(try folder.latestCopy() == .none)

        try folder.write(try backupData(), at: Self.date, timeZone: .gmt)
        guard case .readable(let payload) = try folder.latestCopy() else {
            Issue.record("копия не прочиталась")
            return
        }
        #expect(payload.exportedAt == BackupFormat.normalized(Self.date))
        #expect(payload.expenses.count == 3)

        try temp.create("Траты-последняя.json", contents: "не копия")
        #expect(try folder.latestCopy() == .unreadable)
    }

    @Test("Закладка ведёт в ту же папку и после переименования")
    func bookmark() throws {
        let temp = try TemporaryFolder()
        let bookmark = try AutoBackupFolder.bookmark(for: temp.url)
        let resolved = try AutoBackupFolder.resolve(bookmark: bookmark)
        #expect(resolved.folder.url.standardizedFileURL.resolvingSymlinksInPath().path()
            == temp.url.standardizedFileURL.resolvingSymlinksInPath().path())

        let renamed = temp.root.appending(path: "Копии", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: temp.url, to: renamed)
        let moved = try AutoBackupFolder.resolve(bookmark: bookmark)
        try moved.folder.write(try backupData(), at: Self.date, timeZone: .gmt)
        #expect(FileManager.default.fileExists(atPath: renamed.appending(path: "Траты-последняя.json").path(percentEncoded: false)))
    }

    @Test("Имя папки: iCloud Drive с путём, иначе имя папки")
    func displayName() throws {
        let iCloud = URL(filePath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Траты/", directoryHint: .isDirectory)
        #expect(AutoBackupFolder(url: iCloud).displayName == "iCloud Drive/Траты")
        let nested = URL(filePath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Документы/Траты", directoryHint: .isDirectory)
        #expect(AutoBackupFolder(url: nested).displayName == "iCloud Drive/Документы/Траты")
        let root = URL(filePath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/", directoryHint: .isDirectory)
        #expect(AutoBackupFolder(url: root).displayName == "iCloud Drive")

        let temp = try TemporaryFolder()
        #expect(AutoBackupFolder(url: temp.url).displayName == "Траты")
    }

    @Test("Ошибки файловой системы: нет папки или прав — выбрать заново")
    func classify() {
        #expect(AutoBackupFolder.classify(CocoaError(.fileNoSuchFile)) == .folderUnavailable)
        #expect(AutoBackupFolder.classify(CocoaError(.fileWriteNoPermission)) == .folderUnavailable)
        #expect(AutoBackupFolder.classify(POSIXError(.ENOENT)) == .folderUnavailable)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        ])
        #expect(AutoBackupFolder.classify(wrapped) == .folderUnavailable)
        #expect(AutoBackupFolder.classify(CocoaError(.fileWriteOutOfSpace)) == .writeFailed)
    }
}

// MARK: - Автокопия целиком

@MainActor
@Suite("Автокопия: запись из хранилища")
struct AutoBackupWriterTests {
    static let date = AutoBackupFolderTests.date

    @Test("Пишет при изменениях, пропускает без них")
    func writesOnlyChanges() async throws {
        let container = try BackupFixture.makeContainer()
        let seed = try BackupFixture.seed(container.mainContext)
        let temp = try TemporaryFolder()
        let folder = AutoBackupFolder(url: temp.url)

        let first = try await AutoBackupWriter(modelContainer: container)
            .backUp(to: folder, currencyCode: "BYN", lastFingerprint: nil, trigger: .automatic, now: Self.date, timeZone: .gmt)
        guard case .written(let fingerprint, let exportedAt) = first else {
            Issue.record("копия не записана: \(first)")
            return
        }
        #expect(exportedAt == BackupFormat.normalized(Self.date))
        let restored = try BackupImporter.decode(Data(contentsOf: temp.url.appending(path: AutoBackupFiles.latestFileName)))
        #expect(restored.expenses.count == 3)
        #expect(restored.currencyCode == "BYN")

        let unchanged = try await AutoBackupWriter(modelContainer: container)
            .backUp(to: folder, currencyCode: "BYN", lastFingerprint: fingerprint, trigger: .automatic, now: Self.date + 60, timeZone: .gmt)
        #expect(unchanged == .skipped(.skipUnchanged))

        seed.coffee.note = "Изменено"
        try container.mainContext.save()
        let changed = try await AutoBackupWriter(modelContainer: container)
            .backUp(to: folder, currencyCode: "BYN", lastFingerprint: fingerprint, trigger: .automatic, now: Self.date + 120, timeZone: .gmt)
        guard case .written(let newFingerprint, _) = changed else {
            Issue.record("изменение не записано: \(changed)")
            return
        }
        #expect(newFingerprint != fingerprint)
        let latest = try BackupImporter.decode(Data(contentsOf: temp.url.appending(path: AutoBackupFiles.latestFileName)))
        #expect(latest.expenses.contains { $0.note == "Изменено" })
    }

    @Test("Пустая база сама копию не перезаписывает, по кнопке — да")
    func emptyStore() async throws {
        let container = try BackupFixture.makeContainer()
        let temp = try TemporaryFolder()
        let folder = AutoBackupFolder(url: temp.url)

        let automatic = try await AutoBackupWriter(modelContainer: container)
            .backUp(to: folder, currencyCode: "BYN", lastFingerprint: nil, trigger: .automatic, now: Self.date, timeZone: .gmt)
        #expect(automatic == .skipped(.skipNoExpenses))
        #expect(temp.fileNames.isEmpty)

        let manual = try await AutoBackupWriter(modelContainer: container)
            .backUp(to: folder, currencyCode: "BYN", lastFingerprint: nil, trigger: .manual, now: Self.date, timeZone: .gmt)
        #expect(manual != .skipped(.skipNoExpenses))
        #expect(temp.fileNames == ["Траты-2026-11-10.json", "Траты-последняя.json"])
    }

    @Test("Недоступная папка — ошибка, данные не меняются")
    func unavailableFolder() async throws {
        let container = try BackupFixture.makeContainer()
        try BackupFixture.seed(container.mainContext)
        let temp = try TemporaryFolder()
        try FileManager.default.removeItem(at: temp.url)

        await #expect(throws: AutoBackupError.folderUnavailable) {
            try await AutoBackupWriter(modelContainer: container).backUp(
                to: AutoBackupFolder(url: temp.url), currencyCode: "BYN", lastFingerprint: nil, trigger: .manual
            )
        }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Expense>()) == 3)
    }
}
