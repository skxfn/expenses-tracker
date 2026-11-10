import SwiftUI

/// Шкала-легенда под сеткой (DESIGN.md → Calendar): подпись «Br за день» и пять образцов heat-0…4
/// 44×20, SF 11. Если в строку не помещается (крупный текст) — подпись над образцами.
/// Без `onToggle` — один элемент VoiceOver (`cal.legend.a11y`). С ним образцы — кнопки: нажатие выделяет
/// дни этой ступени в сетке, повторное — снимает; остальные образцы приглушаются, как клетки, а подпись
/// сменяется на «5 дней · 25–50» (`caption`).
struct HeatLegend: View {
    let title: String
    /// Пять подписей по ступеням: «0 · до 25 · 25+ · 50+ · 75+».
    let items: [String]
    let accessibilityText: String
    /// Выделенная ступень и подпись вместо `title`; `nil` — без выделения.
    var selectedLevel: Int?
    var caption: String?
    /// Имена образцов для VoiceOver по ступеням (`cal.legend.step.a11y`).
    var stepAccessibility: [String] = []
    var onToggle: ((Int) -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.md) {
                titleText
                swatches
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                titleText
                swatches
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .modifier(LegendAccessibility(isInteractive: onToggle != nil, label: accessibilityText))
    }

    /// Подпись слева занимает всё место до образцов. Раскладку (в строку или подпись сверху) выбирает
    /// обычная подпись, а подпись выделения ложится поверх и ужимается: выбор ступени не сдвигает шкалу.
    private var titleText: some View {
        Text(verbatim: title)
            .typeStyle(.callout)
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .fixedSize()
            .opacity(caption == nil ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if let caption {
                    Text(verbatim: caption)
                        .typeStyle(.callout)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(CalendarMetrics.legendCaptionMinimumScale)
                }
            }
            // Подпись выделения озвучивает имя образца.
            .accessibilityHidden(onToggle != nil)
    }

    private var swatches: some View {
        HStack(spacing: CalendarMetrics.gridGap) {
            ForEach(Array(items.enumerated()), id: \.offset) { level, item in
                if let onToggle {
                    Button {
                        onToggle(level)
                    } label: {
                        swatch(item, level: level)
                            // Цель касания — 44 в высоту, раскладка — по образцу 20.
                            .padding(.vertical, CalendarMetrics.legendHitOutset)
                            .contentShape(Rectangle())
                            .padding(.vertical, -CalendarMetrics.legendHitOutset)
                    }
                    .buttonStyle(.pressable(Motion.PressScale.circle))
                    .accessibilityLabel(Text(verbatim: level < stepAccessibility.count ? stepAccessibility[level] : item))
                    .accessibilityHint(Text("cal.legend.step.a11y.hint"))
                    .accessibilityAddTraits(selectedLevel == level ? .isSelected : [])
                } else {
                    swatch(item, level: level)
                }
            }
        }
    }

    private func swatch(_ item: String, level: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: CalendarMetrics.legendItemRadius, style: .continuous)
        return Text(verbatim: item)
            .typeStyle(.caption)
            .foregroundStyle(Theme.heatDigits(level))
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minWidth: CalendarMetrics.legendItemWidth, minHeight: CalendarMetrics.legendItemHeight)
            .background(Theme.heat(level), in: shape)
            .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
            .fixedSize()
            .opacity(selectedLevel == nil || selectedLevel == level ? 1 : CalendarMetrics.dimmedOpacity)
    }
}

/// Шкала без выделения — один элемент VoiceOver; с выделением — контейнер с именем шкалы и кнопками-образцами.
private struct LegendAccessibility: ViewModifier {
    let isInteractive: Bool
    let label: String

    func body(content: Content) -> some View {
        if isInteractive {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(verbatim: label))
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
        }
    }
}
