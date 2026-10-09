import SwiftUI
import ExpenseCore

/// Образец категории 46×60, r 6 (DESIGN.md → Category Swatches).
/// Невыбранный — tint с deep-иконкой 22 (в тёмной darktint и иконка tint), в покое тень `swatch-rest`.
/// Выбранный — основной тон с иконкой paper-surface, поднят на 8, тень цвета deep (в тёмной — чёрная),
/// обводка ink 2 со смещением 2 (как в макетах `06-add`, `07-picker`). Кнопку и подпись VoiceOver даёт вызывающий.
struct CategorySwatch: View {
    let iconName: String
    let tone: GouacheTone?
    let isSelected: Bool

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
        shape
            .fill(isSelected ? CategoryPaint.main(tone) : CategoryPaint.area(tone))
            .overlay {
                CategoryIconImage(name: iconName)
                    .frame(width: Theme.Size.swatchIcon * scale, height: Theme.Size.swatchIcon * scale)
                    .foregroundStyle(isSelected ? CategoryPaint.onMain(tone) : CategoryPaint.onArea(tone))
            }
            .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
            .frame(width: Theme.Size.swatchWidth * scale, height: Theme.Size.swatchHeight * scale)
            .modifier(SwatchShadow(isSelected: isSelected, deep: CategoryPaint.shadow(tone), isDark: colorScheme == .dark))
            .overlay {
                if isSelected {
                    SelectionRing(cornerRadius: Theme.Radius.swatch)
                }
            }
            .offset(y: isSelected && !reduceMotion ? -Theme.Size.swatchLift : 0)
            .motion(Motion.select, value: isSelected)
            .accessibilityHidden(true)
    }
}

/// Образец «Все»: paper-surface с контуром 1 separator и подписью SF 13.
struct AllCategoriesSwatch: View {
    let title: LocalizedStringKey

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
        Text(title)
            .typeStyle(.footnote)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: Theme.Size.swatchWidth * scale, height: Theme.Size.swatchHeight * scale)
            .background(Theme.surface, in: shape)
            .overlay { shape.strokeBorder(Theme.separator, lineWidth: 1) }
    }
}

/// Обводка выбранного: 2 pt цветом ink со смещением 2 pt (DESIGN.md → «Фокус»).
struct SelectionRing: View {
    let cornerRadius: CGFloat
    private let width: CGFloat = 2
    private let gap: CGFloat = 2

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius + gap + width / 2, style: .continuous)
            .stroke(Theme.ink, lineWidth: width)
            .padding(-(gap + width / 2))
            .allowsHitTesting(false)
    }
}

private struct SwatchShadow: ViewModifier {
    let isSelected: Bool
    let deep: Color
    let isDark: Bool

    func body(content: Content) -> some View {
        if isSelected {
            let layers = Tokens.Shadow.swatchSelected
            content
                .shadow(color: shadowColor(layers[0]), radius: layers[0].blur / 2, x: layers[0].x, y: layers[0].y)
                .shadow(color: shadowColor(layers[1]), radius: layers[1].blur / 2, x: layers[1].x, y: layers[1].y)
        } else {
            content.paperShadow(Tokens.Shadow.swatchRest)
        }
    }

    private func shadowColor(_ layer: DeepShadowLayer) -> Color {
        isDark ? .black.opacity(layer.darkAlpha) : deep.opacity(layer.lightAlpha)
    }
}

#if DEBUG
#Preview("Образцы") {
    ThemePreview {
        HStack(spacing: 6) {
            CategorySwatch(iconName: "shopping-cart-1-fill", tone: .shalfey, isSelected: true)
            CategorySwatch(iconName: "fork-knife-fill", tone: .abrikos, isSelected: false)
            CategorySwatch(iconName: "car-fill", tone: .kobalt, isSelected: false)
            CategorySwatch(iconName: "movie-fill", tone: .ametist, isSelected: false)
            CategorySwatch(iconName: CategoryPaint.uncategorizedIconName, tone: nil, isSelected: false)
            AllCategoriesSwatch(title: "Все")
        }
        .padding(.top, Theme.Spacing.sm)
    }
}
#endif
