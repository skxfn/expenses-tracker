import SwiftUI

/// Строка «иконка категории — заголовок и подпись — сумма»: расходы, доли категорий, топ трат.
/// На крупных размерах шрифта сумма уходит под текст, чтобы название не рвалось переносами.
struct CategoryAmountRow: View {
    let appearance: CategoryAppearance
    /// По умолчанию — название категории.
    var title: String?
    var subtitle = ""
    let amount: String
    var iconDiameter: CGFloat = 36
    /// Галочка справа — выбранная строка.
    var isSelected = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconView(appearance, diameter: iconDiameter)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    texts
                    amountText
                }
                Spacer(minLength: 0)
            } else {
                texts
                Spacer(minLength: 8)
                amountText
                    .layoutPriority(1)
            }
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title ?? appearance.name)
                .lineLimit(2)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var amountText: some View {
        Text(amount)
            .monospacedDigit()
    }
}

#Preview {
    List {
        CategoryAmountRow(
            appearance: CategoryAppearance(name: "Продукты", iconName: "cart.fill", colorHex: "#2E9D63"),
            subtitle: "Евроопт",
            amount: "23,40 Br"
        )
        CategoryAmountRow(appearance: .uncategorized, amount: "5 Br", isSelected: true)
    }
}
