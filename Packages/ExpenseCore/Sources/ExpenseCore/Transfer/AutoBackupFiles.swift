import Foundation

/// Файлы автокопии в выбранной папке: «последняя» копия и дневные копии с ротацией.
///
/// Имена постоянные, не зависят от языка интерфейса: по ним ротация узнаёт свои файлы. Дефис после «Траты»
/// отличает их от ручной копии («Траты 2026-11-10.json», `app.backupFileName`) — её ротация не удалит.
/// Формат файлов — обычная резервная копия (`BackupExporter`), восстанавливается через «Восстановить из копии».
public enum AutoBackupFiles {
    /// Всегда самая свежая копия — её и восстанавливать после переустановки.
    public static let latestFileName = "Траты-последняя.json"
    /// Сколько дневных копий хранить: дни без изменений копий не дают, поэтому 14 копий — 14 дней с тратами.
    public static let dailyCopiesToKeep = 14

    static let dailyPrefix = "Траты-"
    static let fileExtension = ".json"
    /// Заглушка файла iCloud Drive, который выгружен с устройства: `.Имя.icloud`.
    static let placeholderPrefix = "."
    static let placeholderSuffix = ".icloud"

    /// «Траты-2026-11-10.json»: день — по григорианскому календарю в `timeZone`.
    public static func dailyFileName(for date: Date, timeZone: TimeZone) -> String {
        let day = Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: timeZone).year().month().day()
        return dailyPrefix + date.formatted(day) + fileExtension
    }

    /// День дневной копии («2026-11-10») по имени файла или заглушки iCloud; `nil` — это не дневная копия.
    public static func day(ofDailyFileName fileName: String) -> String? {
        let name = realName(of: fileName)
        guard name.hasPrefix(dailyPrefix), name.hasSuffix(fileExtension) else { return nil }
        let day = String(name.dropFirst(dailyPrefix.count).dropLast(fileExtension.count))
        return isDay(day) ? day : nil
    }

    /// Дневные копии, которые пора удалить: все, кроме `count` самых новых дней. Другие файлы папки не трогает.
    public static func dailyFilesToDelete(among fileNames: [String], keeping count: Int = dailyCopiesToKeep) -> [String] {
        let days = fileNames.compactMap { name in day(ofDailyFileName: name).map { (name, $0) } }
        let kept = Set(Set(days.map(\.1)).sorted(by: >).prefix(max(count, 0)))
        return days.filter { !kept.contains($0.1) }.map(\.0).sorted()
    }

    /// Это «последняя» копия (сам файл или его заглушка iCloud).
    public static func isLatest(_ fileName: String) -> Bool {
        realName(of: fileName) == latestFileName
    }

    /// Имя файла без обёртки заглушки iCloud, в NFC: провайдер файлов может вернуть имя в NFD.
    static func realName(of fileName: String) -> String {
        var name = fileName.precomposedStringWithCanonicalMapping
        if name.hasPrefix(placeholderPrefix), name.hasSuffix(placeholderSuffix),
           name.count > placeholderPrefix.count + placeholderSuffix.count {
            name = String(name.dropFirst(placeholderPrefix.count).dropLast(placeholderSuffix.count))
        }
        return name
    }

    /// «YYYY-MM-DD» с настоящими месяцем и днём.
    private static func isDay(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
            let month = Int(parts[1]), let day = Int(parts[2])
        else { return false }
        return (1...12).contains(month) && (1...31).contains(day)
    }
}
