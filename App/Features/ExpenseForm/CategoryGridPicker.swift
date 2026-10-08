import SwiftUI
import ExpenseCore

/// Сетка категорий с иконками для формы расхода.
struct CategoryGridPicker: View {
    let categories: [ExpenseCategory]
    let selectedID: UUID?
    let onSelect: (ExpenseCategory) -> Void

    @ScaledMetric private var cellWidth: CGFloat = 76

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cellWidth), spacing: 8)], spacing: 8) {
            ForEach(categories) { category in
                cell(for: category, isSelected: category.id == selectedID)
            }
        }
        .padding(.vertical, 4)
    }

    private func cell(for category: ExpenseCategory, isSelected: Bool) -> some View {
        Button {
            onSelect(category)
        } label: {
            VStack(spacing: 6) {
                CategoryIconView(CategoryAppearance(category), diameter: 44)
                Text(category.name)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if category.isArchived {
                    Text("в архиве")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
            .background(
                isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.isArchived ? "\(category.name), в архиве" : category.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
