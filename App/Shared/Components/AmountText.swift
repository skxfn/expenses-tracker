import SwiftUI

/// Сумма Unbounded с табличными цифрами и знаком «⃅» справа (DESIGN.md → Typography, «Правило денег»).
/// Строку готовит форматтер (§5.2: режимы показа сумм), `value` — только для направления анимации цифр
/// (`Double(minor)`, не для расчётов). Внутрь SF-фразы не вставлять: там сумма набирается SF 600.
struct AmountText: View {
    enum Size {
        /// 60 + «⃅» 26 — сумма в шите записи.
        case display
        /// 40 + «⃅» 20 — итог периода.
        case total
        /// 28 + «⃅» 14 — итог в центре кольца.
        case ringTotal
        /// 15 — строки ленты, плитки, быстрые суммы (без «⃅»).
        case inline
        /// 15/600 — сумма в заголовке дня.
        case inlineStrong
    }

    let text: String
    let value: Double
    var size: Size = .total
    /// Символ валюты справа secondary-цветом; `nil` — без него (ячейки, строки, плитки).
    var currency: String?
    /// Подпись VoiceOver по `a11y.money` («142,60 рубля»); `nil` — системное чтение текста.
    var accessibilityText: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) {
            Text(text)
                .typeStyle(amountStyle)
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText(value: value))
            if let currency, let currencyStyle {
                Text(currency)
                    .typeStyle(currencyStyle)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .lineLimit(1)
        .motion(Motion.number, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? [text, currency].compactMap { $0 }.joined(separator: " "))
    }

    private var amountStyle: TypeStyle {
        switch size {
        case .display: .amountDisplay
        case .total: .amountTotal
        case .ringTotal: .amountRingTotal
        case .inline: .amountInline
        case .inlineStrong: .amountInlineStrong
        }
    }

    private var currencyStyle: TypeStyle? {
        switch size {
        case .display: .currencyDisplay
        case .total: .currencyTotal
        case .ringTotal: .currencyRingTotal
        case .inline, .inlineStrong: nil
        }
    }

    private var spacing: CGFloat {
        switch size {
        case .display: Theme.Spacing.md
        case .total: Theme.Spacing.sm
        case .ringTotal, .inline, .inlineStrong: Theme.Spacing.xs
        }
    }
}

#if DEBUG
private struct AmountTextDemo: View {
    @State private var minor: Int64 = 41_230

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            AmountText(text: "12,50", value: 1_250, size: .display, currency: "\u{20C5}")
            AmountText(text: Self.format(minor), value: Double(minor), size: .total, currency: "\u{20C5}")
            AmountText(text: "412,30", value: 41_230, size: .ringTotal, currency: "\u{20C5}")
            HStack {
                AmountText(text: "44,70", value: 4_470, size: .inline)
                Spacer()
                AmountText(text: "57,20", value: 5_720, size: .inlineStrong)
            }
            Button("+ 9,99") { minor += 999 }
        }
    }

    private static func format(_ minor: Int64) -> String {
        "\(minor / 100)," + String(format: "%02lld", minor % 100)
    }
}

#Preview("Суммы") {
    ThemePreview { AmountTextDemo() }
}
#endif
