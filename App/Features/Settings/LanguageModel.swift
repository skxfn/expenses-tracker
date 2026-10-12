import Foundation
import Observation
import SwiftData
import ExpenseCore

/// Экран «Язык»: язык приложения и названия категорий по умолчанию.
///
/// Язык хранится так же, как выбор языка приложения в Настройках iOS (`LanguagePreference` → `AppleLanguages`
/// в домене приложения), и действует со следующего запуска — тексты, даты и суммы меняются вместе. Приложение
/// не может перезапустить себя само, поэтому после выбора — алерт с инструкцией и, если есть что переводить,
/// предложением перевести категории по умолчанию на новый язык.
@Observable
final class LanguageModel {
    /// Алерт после выбора языка, который сменится при следующем запуске.
    struct RestartPrompt: Identifiable {
        let language: AppLanguage
        /// Есть категории по умолчанию, которые можно перевести на `language`.
        let canTranslateCategories: Bool

        var id: String { language.code }
    }

    private(set) var preference: LanguagePreference
    /// Состояние категорий по умолчанию для каждого языка: на каком они сейчас и есть ли что переводить.
    private(set) var categoryStatus: [AppLanguage: DefaultCategoryNamesStatus] = [:]
    var restartPrompt: RestartPrompt?
    /// Ошибка сохранения при переводе категорий (`errorAlert`).
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let translation = AppLanguage.defaultCategoryTranslation

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preference = Self.storedPreference(in: defaults)
    }

    /// Выбор из домена приложения (имя домена — bundle id этой установки: SideStore может дописать к нему Team ID).
    static func storedPreference(in defaults: UserDefaults = .standard) -> LanguagePreference {
        LanguagePreference.stored(in: defaults, domainName: Bundle.main.bundleIdentifier ?? "")
    }

    /// Есть категории, названные как категории по умолчанию на каком-нибудь языке.
    var hasDefaultCategories: Bool {
        categoryStatus.values.contains { $0.named > 0 || $0.translatable > 0 }
    }

    func refresh(context: ModelContext) {
        let store = ExpenseStore(context: context)
        var status: [AppLanguage: DefaultCategoryNamesStatus] = [:]
        for language in AppLanguage.allCases {
            status[language] = try? store.defaultCategoryNamesStatus(translation, language: language.code)
        }
        categoryStatus = status
    }

    func select(_ newValue: LanguagePreference) {
        guard newValue != preference else { return }
        newValue.save(in: defaults)
        preference = newValue
        let language = AppLanguage.atNextLaunch(defaults: defaults)
        guard language != AppLanguage.current else { return }
        restartPrompt = RestartPrompt(
            language: language,
            canTranslateCategories: (categoryStatus[language]?.translatable ?? 0) > 0
        )
    }

    func translateCategories(to language: AppLanguage, context: ModelContext) {
        do {
            try ExpenseStore(context: context).translateDefaultCategories(translation, to: language.code)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        refresh(context: context)
    }
}

extension LanguagePreference {
    /// Ключ подписи в каталоге (`settings.language.*`).
    var titleKey: String {
        switch self {
        case .system: "settings.language.system"
        case .russian: "settings.language.ru"
        case .english: "settings.language.en"
        }
    }
}

extension AppLanguage {
    /// Ключ подписи в каталоге: название языка на нём самом.
    var titleKey: String { "settings.language.\(code)" }
}
