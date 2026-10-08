/// Ключи UserDefaults приложения (подходят и для `@AppStorage`).
public enum SettingsKeys {
    /// `String` — ISO 4217 код валюты приложения.
    public static let currencyCode = "currencyCode"
    /// `Bool` — базовые категории уже создавались, повторно не создавать.
    public static let didSeedDefaultCategories = "didSeedDefaultCategories"
}
