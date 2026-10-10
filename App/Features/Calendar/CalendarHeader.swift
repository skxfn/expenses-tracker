import SwiftUI

/// Шапка календаря: «Октябрь 2026» (Unbounded 28/600 + год Unbounded 20 secondary — `cal.header.month`)
/// и пара ‹ › в одной стеклянной капсуле.
/// ▾ и шита выбора месяца нет (INTEGRATION §8 п. 17): месяц листается ‹ › и свайпом по сетке.
struct CalendarHeader: View {
    let month: String
    let year: String
    let titleAccessibility: String
    let previousAccessibility: String
    let nextAccessibility: String
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(styledTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: titleAccessibility))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            GlassStepperPair(
                previousLabel: LocalizedStringKey(previousAccessibility),
                nextLabel: LocalizedStringKey(nextAccessibility),
                canGoNext: canGoNext,
                onPrevious: onPrevious,
                onNext: onNext
            )
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    /// Месяц и год одним `Text`: при нехватке места уменьшаются вместе, месяц не обрезается.
    private var styledTitle: AttributedString {
        var name = AttributedString(month + " ")
        name.font = TypeStyle.monthTitle.font
        name.tracking = TypeStyle.monthTitle.trackingEm * TypeStyle.monthTitle.size
        name.foregroundColor = Theme.ink
        var number = AttributedString(year)
        number.font = TypeStyle.monthYear.font
        number.foregroundColor = Theme.secondary
        return name + number
    }
}

/// Строка-итог месяца (`cal.summary`): «**412,30 Br** за 8 дней · больше всего 2 окт», SF 15;
/// выделенная сумма — SF 600 графитом. В строку (copy.json: nowrap), на крупном тексте — переносом.
struct CalendarSummaryLine: View {
    let summary: AttributedString

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(styled)
            .typeStyle(.subheadline)
            .foregroundStyle(Theme.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var styled: AttributedString {
        var text = summary
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].inlinePresentationIntent = nil
            text[run.range].font = TypeStyle.callout.font.monospacedDigit()
            text[run.range].foregroundColor = Theme.ink
        }
        return text
    }
}
