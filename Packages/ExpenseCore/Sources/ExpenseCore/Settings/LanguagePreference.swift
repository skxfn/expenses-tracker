import Foundation

/// Язык интерфейса, выбранный в настройках приложения (`settings.language`): «Как в системе» или язык приложения.
///
/// Хранится там же, где его хранит выбор языка приложения в Настройках iOS, — `AppleLanguages` в домене
/// приложения; список языков системы лежит в глобальном домене и не меняется. iOS читает этот ключ при запуске
/// (по нему `Bundle.main.preferredLocalizations`), поэтому новый язык действует со следующего запуска:
/// тексты, даты и суммы (`AppLanguage`, `Locale.app`, `L10n`) переключаются вместе.
public enum LanguagePreference: String, CaseIterable, Sendable {
    case system
    case russian = "ru"
    case english = "en"

    /// Ключ UserDefaults со списком языков пользователя (его же задаёт `-AppleLanguages` в аргументах запуска).
    public static let appleLanguagesKey = "AppleLanguages"

    /// Языки интерфейса приложения; первый — исходный, его iOS берёт, если ни один из языков пользователя не подошёл.
    public static let interfaceLanguageCodes = ["ru", "en"]

    /// Выбор, сохранённый в домене приложения `domainName` (bundle id приложения, в тестах — имя suite).
    /// Читается сам домен, а не `defaults.object(forKey:)`: тот без выбора вернул бы список языков системы.
    public static func stored(in defaults: UserDefaults, domainName: String) -> LanguagePreference {
        let languages = defaults.persistentDomain(forName: domainName)?[appleLanguagesKey] as? [String]
        guard let code = languages?.first.flatMap(languageCode(of:)) else { return .system }
        return LanguagePreference(rawValue: code) ?? .system
    }

    /// Сохраняет выбор: язык — `AppleLanguages = [код]`, «Как в системе» — ключ удаляется из домена приложения.
    public func save(in defaults: UserDefaults) {
        switch self {
        case .system: defaults.removeObject(forKey: Self.appleLanguagesKey)
        case .russian, .english: defaults.set([rawValue], forKey: Self.appleLanguagesKey)
        }
    }

    /// Язык интерфейса для списка языков пользователя, как его выбирает iOS: первый язык из списка, который есть
    /// в приложении, иначе исходный (ru).
    public static func interfaceLanguageCode(for preferredLanguages: [String]) -> String {
        preferredLanguages.lazy
            .compactMap(languageCode(of:))
            .first(where: interfaceLanguageCodes.contains) ?? interfaceLanguageCodes[0]
    }

    /// «ru-BY» → «ru».
    private static func languageCode(of identifier: String) -> String? {
        Locale(identifier: identifier).language.languageCode?.identifier
    }
}
