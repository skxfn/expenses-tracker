/// Ключи UserDefaults приложения (подходят и для `@AppStorage`).
public enum SettingsKeys {
    /// `String` — ISO 4217 код валюты приложения.
    public static let currencyCode = "currencyCode"
    /// `String` — `CurrencySymbolStyle.rawValue`, обозначение BYN в суммах: знак или код.
    public static let currencySymbolStyle = "currencySymbolStyle"
    /// `Bool` — базовые категории уже создавались, повторно не создавать.
    public static let didSeedDefaultCategories = "didSeedDefaultCategories"
    /// `String` — `HomeOverviewStyle.rawValue`, обзор категорий на вкладке «Траты».
    public static let homeOverviewStyle = "homeOverviewStyle"
    /// `String` — `StatsCategoryView.rawValue`, вид раздела категорий в статистике.
    public static let statsCategoryView = "statsCategoryView"
    /// `Bool` — ИИ-запись включена (по умолчанию выключена: без неё ни одного сетевого запроса).
    public static let assistantEnabled = "assistantEnabled"
    /// `String` — `AssistantPreset.rawValue`.
    public static let assistantPreset = "assistantPreset"
    /// `String` — `AssistantAPIFormat.rawValue`.
    public static let assistantFormat = "assistantFormat"
    /// `String` — адрес сервера модели, как ввёл пользователь.
    public static let assistantBaseURL = "assistantBaseURL"
    /// `String` — имя модели.
    public static let assistantModel = "assistantModel"
    /// `String` — `ReceiptGroupingMode.rawValue`, режим чека, выбранный в прошлый раз.
    public static let assistantReceiptMode = "assistantReceiptMode"
}
