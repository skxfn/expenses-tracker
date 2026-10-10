import SwiftUI
import UIKit
import ExpenseCore

/// Иконка категории MingCute Fill из `Assets.xcassets/Categories` (шаблон: цвет задаёт `foregroundStyle`).
/// Неизвестное имя (в т. ч. старое имя SF Symbol до миграции) — «Три точки», как `migration.json` → iconFallback.
struct CategoryIconImage: View {
    let name: String

    var body: some View {
        Image(CategoryIconAsset.resolvedName(name))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}

nonisolated enum CategoryIconAsset {
    /// `design/migration.json` → iconFallback.
    static let fallbackName = "more-3-fill"

    static func resolvedName(_ name: String) -> String {
        UIImage(named: name) == nil ? fallbackName : name
    }
}

/// Плашка иконки категории: 36/r10 с иконкой 20 или 52/r15 с иконкой 26 (design.json → icons).
/// `.area` — tint с deep-иконкой (в тёмной darktint с иконкой цветом tint); `.main` — основной тон с иконкой
/// paper-surface (раскрытая категория в «Полосах»). `tone == nil` — «Без категории» (нейтраль).
/// Декоративная: подпись даёт текст рядом.
struct CategoryPlaque: View {
    enum Size {
        /// 36 × 36, r 10, иконка 20 — лента, списки, «Полосы».
        case regular
        /// 52 × 52, r 15, иконка 26 — превью редактора категории.
        case large
    }

    enum Fill {
        case area
        case main
    }

    let iconName: String
    let tone: GouacheTone?
    var size: Size = .regular
    var fill: Fill = .area

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let metrics = metrics
        RoundedRectangle(cornerRadius: metrics.radius * scale, style: .continuous)
            .fill(background)
            .frame(width: metrics.side * scale, height: metrics.side * scale)
            .overlay {
                CategoryIconImage(name: iconName)
                    .frame(width: metrics.icon * scale, height: metrics.icon * scale)
                    .foregroundStyle(foreground)
            }
            .accessibilityHidden(true)
    }

    private var metrics: (side: CGFloat, radius: CGFloat, icon: CGFloat) {
        switch size {
        case .regular: (Theme.Size.plaque, Theme.Radius.plaque, Theme.Size.plaqueIcon)
        case .large: (Theme.Size.plaqueLarge, Theme.Radius.plaqueLarge, Theme.Size.plaqueLargeIcon)
        }
    }

    private var background: Color {
        switch fill {
        case .area: CategoryPaint.area(tone)
        case .main: CategoryPaint.main(tone)
        }
    }

    private var foreground: Color {
        switch fill {
        case .area: CategoryPaint.onArea(tone)
        case .main: CategoryPaint.onMain(tone)
        }
    }
}

#if DEBUG
#Preview("Плашки") {
    ThemePreview {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                CategoryPlaque(iconName: "basket-fill", tone: .shalfey)
                CategoryPlaque(iconName: "fork-knife-fill", tone: .abrikos)
                CategoryPlaque(iconName: "bus-fill", tone: .kobalt)
                CategoryPlaque(iconName: "basket-fill", tone: .shalfey, fill: .main)
                CategoryPlaque(iconName: CategoryPaint.uncategorizedIconName, tone: nil)
            }
            HStack(spacing: Theme.Spacing.sm) {
                CategoryPlaque(iconName: "teacup-fill", tone: .abrikos, size: .large)
                CategoryPlaque(iconName: "gift-fill", tone: .krapplak, size: .large, fill: .main)
            }
        }
    }
}
#endif
