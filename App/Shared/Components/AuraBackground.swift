import SwiftUI
import ExpenseCore

/// Аура (design.json → aura, §3.2): 2–3 пятна `EllipticalGradient` цветом tint крупнейших категорий
/// периода (в тёмной — darktint) поверх фона экрана. Это фон, не стекло: под ним видно стекло хрома.
/// Без категорий — только фон (первый запуск). В шите записи — одно пятно цвета выбранной категории у нижнего края.
struct AuraBackground: View {
    /// Пятно: центр и полуоси в долях кадра, непрозрачность в центре (к краю — 0).
    struct Spot: Sendable {
        let center: UnitPoint
        let radius: CGSize
        let opacity: Double
    }

    /// Тоны крупнейших категорий, по убыванию суммы; берутся первые `layout.count`.
    let tones: [GouacheTone]
    /// К какому краю прижаты пятна: `.top` — экраны, `.bottom` — шит записи над клавиатурой.
    var edge: VerticalEdge = .top
    /// Фон под пятнами: экран — canvas, шит — canvasElevated.
    var base: Color = Theme.canvas
    var layout: [Spot] = AuraBackground.defaultLayout

    /// Первые два пятна — `aura.example` (60 % × 80 % в 10 % / 95 % сверху, α .85 / .9).
    /// Третье в design.json не задано — подобрано по макетам `02-home-ring`, `12-settings`.
    static let defaultLayout: [Spot] = [
        Spot(center: UnitPoint(x: 0.10, y: 0), radius: CGSize(width: 0.6, height: 0.8), opacity: 0.85),
        Spot(center: UnitPoint(x: 0.95, y: 0), radius: CGSize(width: 0.6, height: 0.8), opacity: 0.9),
        Spot(center: UnitPoint(x: 0.55, y: 0.22), radius: CGSize(width: 0.45, height: 0.35), opacity: 0.6),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                base
                ForEach(Array(zip(tones, layout).enumerated()), id: \.offset) { _, pair in
                    spot(pair.1, color: pair.0.area, in: proxy.size)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func spot(_ spot: Spot, color: Color, in size: CGSize) -> some View {
        let y = edge == .top ? spot.center.y : 1 - spot.center.y
        return EllipticalGradient(
            colors: [color.opacity(spot.opacity), color.opacity(0)],
            center: .center,
            startRadiusFraction: 0,
            endRadiusFraction: 0.5
        )
        .frame(width: size.width * spot.radius.width * 2, height: size.height * spot.radius.height * 2)
        .position(x: size.width * spot.center.x, y: size.height * y)
    }
}

#if DEBUG
#Preview("Аура") {
    ThemePreview {
        AuraBackground(tones: [.shalfey, .abrikos, .ametist])
            .frame(height: 300)
    }
}
#endif
