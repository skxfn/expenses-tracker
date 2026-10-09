import Foundation

/// Строки `Resources/Localizable.xcstrings`. Каталог генерирует `scripts/gen_strings.py` из `design/copy.json`,
/// ключ — id строки (`add.save`, `stats.summary.meta`, разбиения — `add.discard.keep`).
///
/// Строка без аргументов — прямо по ключу: `Text("add.save")`, `Button("add.discard.keep") { … }`,
/// вне View — `String(localized: "add.save")`. Ключ из переменной — `Text(LocalizedStringKey(key))`:
/// интерполяция в литерале (`Text("cat.color.names.\(tone)")`) превращает ключ в формат и строку не найдёт.
/// Строка с `%@` / `%lld` — через `L10n.format`; строка с выделением `**…**` — через `L10n.attributed`.
nonisolated enum L10n {
    /// Локаль форматирования. Форму «1 трата / 2 траты / 5 трат» Foundation выбирает по правилам
    /// этой локали, а не языка строки: с `Locale.current` = en получится «5 траты».
    static let locale = Locale(identifier: "ru")

    /// Строка каталога с подстановками: `%@` — `String`, `%lld` — `Int` (плюрализация ru).
    /// Порядок аргументов — как в комментарии ключа в каталоге.
    ///
    ///     L10n.format("stats.summary.meta", 18, "51,54 Br")  // «18 трат · в среднем 51,54 Br в день»
    static func format(_ key: String, _ args: any CVarArg...) -> String {
        formatted(key, arguments: args)
    }

    /// Строка с выделением (`**…**` в каталоге, список — `EMPHASIZED` в gen_strings.py).
    /// Выделенный фрагмент приходит с `inlinePresentationIntent == .stronglyEmphasized`; без стилизации
    /// SwiftUI покажет его жирным (700). По DESIGN.md нужен SF 600 графитом — перебрать `runs`:
    ///
    ///     var text = L10n.attributed("home.compare", "38 Br", String(localized: "home.compare.month.current"))
    ///     for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
    ///         text[run.range].inlinePresentationIntent = nil        // иначе поверх веса ляжет bold
    ///         text[run.range].font = .subheadline.weight(.semibold) // SF 600 (callout 15)
    ///         text[run.range].foregroundColor = .primary            // графит; остальное — .secondary у Text
    ///     }
    ///     Text(text).foregroundStyle(.secondary)
    ///
    /// Строковые аргументы экранируются: имя категории со `*` или `_` не станет разметкой.
    static func attributed(_ key: String, _ args: any CVarArg...) -> AttributedString {
        let escaped: [any CVarArg] = args.map { arg in
            if let string = arg as? String { return escapingMarkdown(string) }
            return arg
        }
        let text = formatted(key, arguments: escaped)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private static func formatted(_ key: String, arguments: [any CVarArg]) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: locale, arguments: arguments)
    }

    /// Markdown (CommonMark) позволяет экранировать обратной косой чертой любой знак ASCII-пунктуации.
    private static func escapingMarkdown(_ text: String) -> String {
        var result = ""
        for character in text {
            if character.isASCII, character.isPunctuation || character.isSymbol {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }
}
