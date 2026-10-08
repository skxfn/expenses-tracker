import SwiftUI

/// Строка расхода: иконка категории, категория и заметка, сумма.
struct ExpenseRowView: View {
    let appearance: CategoryAppearance
    let note: String
    let amount: String

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconView(appearance)
            VStack(alignment: .leading, spacing: 2) {
                Text(appearance.name)
                    .lineLimit(2)
                if !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(amount)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        ExpenseRowView(
            appearance: CategoryAppearance(name: "Продукты", iconName: "cart.fill", colorHex: "#2E9D63"),
            note: "Евроопт",
            amount: "23,40 Br"
        )
        ExpenseRowView(appearance: .uncategorized, note: "", amount: "5 Br")
    }
}
