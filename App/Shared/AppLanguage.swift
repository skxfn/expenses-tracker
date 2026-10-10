import Foundation
import ExpenseCore

/// Язык интерфейса: iOS выбирает его из списка языков пользователя среди локализаций приложения
/// (ru — исходный, en; `Bundle.main.preferredLocalizations`). Числа и даты следуют языку, а не региону
/// устройства (INTEGRATION §5.5): английский с регионом Беларусь дал бы «1 412,60», русский с регионом США —
/// «1,412.60».
nonisolated enum AppLanguage: Sendable {
    case russian
    case english

    /// Язык этого запуска: смена языка в Настройках iOS перезапускает приложение.
    static let current = AppLanguage(localization: Bundle.main.preferredLocalizations.first ?? "ru")

    init(localization: String) {
        self = Locale(identifier: localization).language.languageCode == .english ? .english : .russian
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
