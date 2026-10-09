import Foundation

/// Строки `Resources/Localizable.xcstrings`. Каталог генерирует `scripts/gen_strings.py` из `design/copy.json`,
/// ключ — id строки (`add.save`, `stats.summary.meta`, разбиения — `add.discard.keep`).
///
/// Строка без аргументов — прямо по ключу: `Text("add.save")`, `Button("add.discard.keep") { … }`,
/// вне View — `String(localized: "add.save")`. Ключ из переменной — `Text(LocalizedStringKey(key))`:
/// интерполяция в литерале (`Text("cat.color.names.\(tone)")`) превращает ключ в формат и строку не найдёт.
/// Строка с `%@` / `%lld` — через `L10n.format`.
nonisolated enum L10n {
    /// Локаль форматирования. Форму «1 трата / 2 траты / 5 трат» Foundation выбирает по правилам
    /// этой локали, а не языка строки: с `Locale.current` = en получится «5 траты».
    static let locale = Locale(identifier: "ru")

    /// Строка каталога с подстановками: `%@` — `String`, `%lld` — `Int` (плюрализация ru).
    /// Порядок аргументов — как в комментарии ключа в каталоге.
    ///
    ///     L10n.format("stats.summary.meta", 18, "51,54 Br")  // «18 трат · в среднем 51,54 Br в день»
    static func format(_ key: String, _ args: any CVarArg...) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: locale, arguments: args)
    }
}
