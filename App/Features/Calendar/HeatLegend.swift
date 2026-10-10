import SwiftUI

/// Шкала-легенда под сеткой (DESIGN.md → Calendar): подпись «Br за день» и пять образцов heat-0…4
/// 44×20, SF 11. Один элемент VoiceOver (`cal.legend.a11y`). Если в строку не помещается
/// (крупный текст) — подпись над образцами.
struct HeatLegend: View {
    let title: String
    /// Пять подписей по ступеням: «0 · до 25 · 25+ · 50+ · 75+».
    let items: [String]
    let accessibilityText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.md) {
                titleText
                Spacer(minLength: 0)
                swatches
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                titleText
                swatches
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var titleText: some View {
        Text(verbatim: title)
            .typeStyle(.callout)
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var swatches: some View {
        HStack(spacing: CalendarMetrics.gridGap) {
            ForEach(Array(items.enumerated()), id: \.offset) { level, item in
                let shape = RoundedRectangle(cornerRadius: CalendarMetrics.legendItemRadius, style: .continuous)
                Text(verbatim: item)
                    .typeStyle(.caption)
                    .foregroundStyle(Theme.heatDigits(level))
                    .lineLimit(1)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(minWidth: CalendarMetrics.legendItemWidth, minHeight: CalendarMetrics.legendItemHeight)
                    .background(Theme.heat(level), in: shape)
                    .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
                    .fixedSize()
            }
        }
    }
}
