import SwiftUI
import ExpenseCore

/// Липкий заголовок дня (DESIGN.md → Day Header, `01-home`): стеклянная капсула 36 (`glass-in`) с полями 14,
/// «**Сегодня** · чт, 8 окт» SF 15/600 (выделенное — графитом, дата — secondary), сумма дня Unbounded 15/600.
/// На крупном шрифте текст переносится, капсула растёт в скруглённый прямоугольник того же радиуса.
/// На размерах доступности дата и сумма — в две строки: в ряд с суммой «Сегодня» рвалось посередине слова.
struct FeedDayHeader: View {
    let title: AttributedString
    let totalMinor: Int64
    let accessibilityText: String

    @Environment(\.moneyFormatter) private var money
    @Environment(\.fontResolutionContext) private var fontContext
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Поля капсулы по бокам (DESIGN.md → Day Header: 14).
    private static let horizontalPadding: CGFloat = 14

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    titleText
                    amountText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    titleText
                    Spacer(minLength: Theme.Spacing.sm)
                    amountText
                }
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: Theme.Size.dayHeader)
        .glass(.inContent, in: RoundedRectangle(cornerRadius: Theme.Size.dayHeader / 2, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityAddTraits(.isHeader)
    }

    private var titleText: some View {
        Text(HomePhrase.styled(title, emphasis: TypeStyle.callout, in: fontContext))
            .typeStyle(.callout)
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var amountText: some View {
        AmountText(
            text: money.string(fromMinor: totalMinor, style: .plain),
            value: Double(totalMinor),
            size: .inlineStrong
        )
        .fixedSize()
    }
}
