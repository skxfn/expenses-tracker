import Foundation
import ExpenseCore

/// Валюта в списке выбора: ISO-код и название на языке системы.
struct CurrencyOption: Identifiable, Hashable {
    let code: String
    /// «Белорусский рубль». Если система валюту не знает — сам код.
    let name: String

    var id: String { code }

    init(code: String, locale: Locale = .current) {
        self.code = code
        name = locale.localizedString(forCurrencyCode: code).map(Self.capitalizedFirstLetter) ?? code
    }

    static let popular = CurrencySettings.popularCodes.map { CurrencyOption(code: $0) }
    static let other = CurrencySettings.otherCodes.map { CurrencyOption(code: $0) }

    /// «BYN — Белорусский рубль».
    static func displayName(for code: String) -> String {
        let option = CurrencyOption(code: code)
        return option.name == code ? code : "\(code) — \(option.name)"
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty
            || code.localizedCaseInsensitiveContains(query)
            || name.localizedCaseInsensitiveContains(query)
    }

    private static func capitalizedFirstLetter(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
