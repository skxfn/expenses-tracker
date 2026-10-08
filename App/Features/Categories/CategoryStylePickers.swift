import SwiftUI
import ExpenseCore

/// Свотчи цветов из `CategoryPalette`.
struct ColorSwatchPicker: View {
    @Binding var selection: String

    @ScaledMetric private var size: CGFloat = 34

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: size + 10), spacing: 8)], spacing: 8) {
            ForEach(Array(CategoryPalette.colors.enumerated()), id: \.element) { index, hex in
                let isSelected = hex.caseInsensitiveCompare(selection) == .orderedSame
                Button {
                    selection = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: size, height: size)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(3)
                        .overlay {
                            Circle().strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Цвет \(index + 1) из \(CategoryPalette.colors.count)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// Сетка иконок одной группы `CategoryIconCatalog`.
struct IconGridPicker: View {
    let symbols: [String]
    let colorHex: String
    @Binding var selection: String

    @ScaledMetric private var size: CGFloat = 40

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: size + 8), spacing: 8)], spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                let isSelected = symbol == selection
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .frame(width: size, height: size)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(
                            isSelected ? Color(hex: colorHex) : Color(uiColor: .tertiarySystemFill),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
