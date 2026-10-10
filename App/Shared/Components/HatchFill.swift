import SwiftUI
import ExpenseCore

/// Штриховка «без подкатегории» (design.json → hatch): 45° «/», полоса 1,4 основным тоном по фону 2,1
/// (шаг 3,5); фон — tint, в тёмной — darktint. Заполняет предложенный размер; форму задаёт `clipShape` снаружи.
struct HatchFill: View {
    let stripe: Color
    let ground: Color

    /// Ширина полосы и шаг, pt (перпендикулярно полосам).
    static let stripeWidth: CGFloat = 1.4
    static let period: CGFloat = 3.5

    init(tone: GouacheTone) {
        stripe = tone.hatchStripe
        ground = tone.hatchGround
    }

    init(stripe: Color, ground: Color) {
        self.stripe = stripe
        self.ground = ground
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))
            let reach = (size.width + size.height) / 2 + Self.period
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .degrees(45))
            var stripes = Path()
            var x = -reach
            while x < reach {
                stripes.addRect(CGRect(x: x, y: -reach, width: Self.stripeWidth, height: reach * 2))
                x += Self.period
            }
            context.fill(stripes, with: .color(stripe))
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Штриховка") {
    ThemePreview {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach([GouacheTone.grafit, .shalfey, .pion, .abrikos], id: \.self) { tone in
                HatchFill(tone: tone)
                    .frame(width: 70, height: 40)
                    .clipShape(.rect(cornerRadius: Theme.Radius.tile, style: .continuous))
            }
        }
    }
}
#endif
