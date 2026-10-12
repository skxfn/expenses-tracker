import Foundation
import ExpenseCore

/// Язык интерфейса: iOS выбирает его из списка языков пользователя среди локализаций приложения
/// (ru — исходный, en; `Bundle.main.preferredLocalizations`). Числа и даты следуют языку, а не региону
/// устройства (INTEGRATION §5.5): английский с регионом Беларусь дал бы «1 412,60», русский с регионом США —
/// «1,412.60». Выбор языка в настройках приложения (`LanguagePreference`) iOS учитывает при запуске.
nonisolated enum AppLanguage: Sendable, CaseIterable {
    case russian
    case english

    /// Язык этого запуска: смена языка в Настройках iOS перезапускает приложение.
    static let current = AppLanguage(localization: Bundle.main.preferredLocalizations.first ?? "ru")

    init(localization: String) {
        self = Locale(identifier: localization).language.languageCode == .english ? .english : .russian
    }

    /// Язык следующего запуска — так же, как его выберет iOS: по выбору в настройках приложения
    /// (`LanguagePreference`) или по списку языков системы.
    static func atNextLaunch(defaults: UserDefaults = .standard) -> AppLanguage {
        let languages = defaults.stringArray(forKey: LanguagePreference.appleLanguagesKey) ?? []
        return AppLanguage(localization: LanguagePreference.interfaceLanguageCode(for: languages))
    }

    /// Перевод названий базовых категорий между языками интерфейса.
    static var defaultCategoryTranslation: DefaultCategoryTranslation {
        DefaultCategoryTranslation(names: Dictionary(uniqueKeysWithValues: allCases.map { ($0.code, $0.defaultCategoryNames) }))
    }

    /// Названия базовых категорий на этом языке, независимо от языка интерфейса: `default.group.N`
    /// из каталога строк этого языка (`<код>.lproj` в бандле), в порядке `DefaultCategories.all`.
    var defaultCategoryNames: [String] {
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        return DefaultCategories.all.indices.map {
            bundle.localizedString(forKey: "default.group.\($0 + 1)", value: nil, table: nil)
        }
    }

    /// Язык строк каталога — по нему Foundation выбирает форму числа («5 трат», «5 expenses»).
    var code: String {
        switch self {
        case .russian: "ru"
        case .english: "en"
        }
    }

    /// Локаль чисел и дат: «1 412,60» / «1,412.60».
    var locale: Locale {
        switch self {
        case .russian: Locale(identifier: "ru_RU")
        case .english: Locale(identifier: "en_US")
        }
    }

    /// Даты и названия месяцев и дней недели: D7 (ru) или E8 (en).
    func dateFormatter(calendar: Calendar, now: Date) -> any DateTextFormatter {
        switch self {
        case .russian: RussianDateFormatter(calendar: calendar, now: now)
        case .english: EnglishDateFormatter(calendar: calendar, now: now)
        }
    }
}
