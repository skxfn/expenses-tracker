#if DEBUG
import SwiftUI
import CoreText
import ExpenseCore

/// Спайк знака рубля U+20C5 (design/INTEGRATION.md §3.3.1): подстановка `BYNSign` в Unbounded и SF,
/// фраза с выделением, обе настройки «Обозначение», эмодзи и другие письменности в той же строке.
/// Открыть: `-debugShowcase currencySign`; Dynamic Type и тёмная тема — настройками симулятора.
struct CurrencySignShowcase: View {
    @Environment(\.fontResolutionContext) private var fontContext

    private let sign = MoneyFormatter(currencyCode: "BYN", locale: .app, symbolStyle: .sign)
    private let code = MoneyFormatter(currencyCode: "BYN", locale: .app, symbolStyle: .code)

    var body: some View {
        ShowcasePageLayout(title: "Знак рубля") {
            ForEach(report, id: \.self) { line in
                Text(verbatim: line)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(Theme.ink)
            }
            ShowcaseSection(title: "Подстановка не мешает системной: эмодзи, иероглифы, арабский") {
                Text(verbatim: "☕️ Кофе · 咖啡 · قهوة · 38\u{00A0}\u{20C5}")
                    .typeStyle(.body)
            }
            ShowcaseSection(title: "Без подстановки (.font(.body)): квадрат") {
                Text(verbatim: "38\u{00A0}\u{20C5}").font(.body)
            }
            ShowcaseSection(title: "Unbounded: AmountText, знак и код") {
                ForEach([sign, code], id: \.symbolStyle) { money in
                    AmountText(text: money.string(fromMinor: 41_230, style: .plain), value: 41_230, size: .total, currency: money.currencySymbol)
                }
                AmountText(text: "12,50", value: 1_250, size: .display, currency: sign.currencySymbol)
                AmountText(text: "1 412,30", value: 141_230, size: .ringTotal, currency: sign.currencySymbol)
            }
            ShowcaseSection(title: "SF: typeStyle, вывод форматтера") {
                ForEach([sign, code], id: \.symbolStyle) { money in
                    Text(verbatim: L10n.format("stats.summary.meta", 18, money.string(fromMinor: 5_154)))
                        .typeStyle(.subheadline)
                    Text(verbatim: L10n.format("period.range.meta", 15, money.string(fromMinor: 74_200)))
                        .typeStyle(.body)
                    Text(verbatim: L10n.format("cal.legend.title", money.currencySymbol))
                        .typeStyle(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
            ShowcaseSection(title: "Фраза с выделением (L10n.attributed)") {
                ForEach([sign, code], id: \.symbolStyle) { money in
                    Text(compare(money))
                        .typeStyle(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func compare(_ money: MoneyFormatter) -> AttributedString {
        var text = L10n.attributed("home.compare", money.string(fromMinor: 3_800, style: .difference),
                                   String(localized: "home.compare.month.current"))
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].inlinePresentationIntent = nil
            text[run.range].font = CurrencySignFont.font(TypeStyle.callout.font.monospacedDigit(), in: fontContext)
            text[run.range].foregroundColor = Theme.ink
        }
        return text
    }

    /// Какой шрифт CoreText берёт для U+20C5 без подстановки и с ней; табличные цифры после подстановки.
    private var report: [String] {
        var lines = ["Семейства: " + UIFont.familyNames.filter { $0.contains("BYN") }.joined(separator: ", ")]
        for (name, style) in [("SF body", TypeStyle.body), ("Unbounded 40", TypeStyle.amountTotal)] {
            let native = style.font.resolve(in: fontContext).ctFont
            let cascaded = style.font(in: fontContext).resolve(in: fontContext).ctFont
            lines.append("\(name) \(Int(CTFontGetSize(native))) pt: без подстановки → \(fallbackName(native)), с ней → \(fallbackName(cascaded))")
        }
        let total = TypeStyle.amountTotal.font(in: fontContext).resolve(in: fontContext).ctFont
        lines.append("tnum после подстановки, 1111,11 / 8888,88: \(width("1111,11", total)) / \(width("8888,88", total))")
        let body = TypeStyle.body
        let plain = body.font.resolve(in: fontContext).ctFont
        let cascaded = body.font(in: fontContext).resolve(in: fontContext).ctFont
        lines.append("SF body «Настройки»: \(width("Настройки", plain)) → \(width("Настройки", cascaded))")
        return lines
    }

    private func fallbackName(_ font: CTFont) -> String {
        let used = CTFontCreateForString(font, "\u{20C5}" as CFString, CFRange(location: 0, length: 1))
        return CTFontCopyFamilyName(used) as String
    }

    private func width(_ string: String, _ font: CTFont) -> String {
        let attributed = NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        return String(format: "%.1f", CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
#endif
