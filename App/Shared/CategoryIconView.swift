import SwiftUI

/// Иконка категории: белый символ в цветном круге. Размер растёт вместе с Dynamic Type.
/// Декоративная: VoiceOver её пропускает, подпись даёт текст рядом.
struct CategoryIconView: View {
    let iconName: String
    let colorHex: String
    var diameter: CGFloat = 36

    @ScaledMetric private var scale: CGFloat = 1

    init(iconName: String, colorHex: String, diameter: CGFloat = 36) {
        self.iconName = iconName
        self.colorHex = colorHex
        self.diameter = diameter
    }

    init(_ appearance: CategoryAppearance, diameter: CGFloat = 36) {
        self.init(iconName: appearance.iconName, colorHex: appearance.colorHex, diameter: diameter)
    }

    var body: some View {
        let size = diameter * scale
        Image(systemName: iconName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex), in: Circle())
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        CategoryIconView(iconName: "cart.fill", colorHex: "#2E9D63")
        CategoryIconView(.uncategorized, diameter: 48)
    }
}
