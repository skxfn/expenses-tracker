import SwiftUI

/// Токены движения (design.json → motion, §3.6). Уход быстрее появления, пружины без отскока.
/// Без анимации (`motionNone`): набор цифр суммы, переключение вкладок, появление клавиатуры,
/// переходы в настройках, обычный скролл.
nonisolated enum Motion {
    /// Отклик нажатия (не для стекла с `.interactive()` — у него свой).
    static let press: Animation = .easeOut(duration: 0.12)
    /// Дискретный выбор: образец, дата, период.
    static let select: Animation = .snappy(duration: 0.22)
    /// Смена формы и геометрии.
    static let morph: Animation = .spring(duration: 0.4, bounce: 0.12)
    /// Появление.
    static let enter: Animation = .spring(duration: 0.32, bounce: 0)
    /// Уход.
    static let exit: Animation = .easeOut(duration: 0.18)
    /// Смена сумм и итогов; вместе с `.contentTransition(.numericText(value:))`.
    static let number: Animation = .snappy(duration: 0.25)
    /// Раскрытие категории (все четыре вида).
    static let vizExpand: Animation = .spring(response: 0.5, dampingFraction: 0.86)
    /// Сворачивание: сначала гаснут оттенки (`vizShadesOut`), затем форма.
    static let vizCollapse: Animation = .spring(response: 0.35, dampingFraction: 0.9).delay(0.12)
    static let vizShadesOut: Animation = .easeOut(duration: 0.12)
    /// Смена вида визуализации; переход — `vizSwitchTransition`.
    static let vizSwitch: Animation = .smooth(duration: 0.3)
    @MainActor static var vizSwitchTransition: AnyTransition {
        AnyTransition(.blurReplace).combined(with: .scale(scale: 0.97))
    }
    /// Пилюля сегмента и переключателя (`matchedGeometryEffect`).
    static let segmentPill: Animation = .spring(response: 0.32, dampingFraction: 0.86)
    /// Подсказка дня на графике.
    static let chartTooltip: Animation = .snappy(duration: 0.24)
    /// Подсветка новой строки tint 12 % гаснет после «Сохранить».
    static let saveHighlightFade: Animation = .easeOut(duration: 0.8)
    static let saveHighlightOpacity: Double = 0.12
    /// «Ещё одна»: сумма улетает вверх (y −24, opacity 0, blur 4).
    static let anotherOne: Animation = .easeOut(duration: 0.22)

    /// Проявление оттенка подкатегории `index` со стаггером.
    static func vizShade(index: Int) -> Animation {
        .spring(response: 0.35, dampingFraction: 0.9).delay(0.14 + 0.06 * Double(index))
    }

    /// Масштаб при нажатии (DESIGN.md → Buttons).
    enum PressScale {
        static let tile: CGFloat = 0.97
        static let row: CGFloat = 0.985
        static let circle: CGFloat = 0.94
    }

    /// Тряска «Сохранить» без суммы: смещения по x за 0,3 с.
    static let errorShakeOffsets: [CGFloat] = [0, -8, 8, -5, 5, 0]
    static let errorShakeDuration: TimeInterval = 0.3

    // MARK: Reduce Motion

    /// Замена любого движения при «Уменьшении движения»: только opacity.
    static let reduced: Animation = .easeOut(duration: 0.18)

    /// Анимация с учётом Reduce Motion — для `withAnimation` вне View.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }

    /// Переход с учётом Reduce Motion: вместо полёта и масштаба — только opacity.
    static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

/// Тактильный отклик (design.json → haptics). Применять через `.sensoryFeedback(_:trigger:)`.
nonisolated enum Haptic {
    /// Дискретный выбор: категория, дата, период, день, цвет, иконка, перебор сегментов.
    static let selection: SensoryFeedback = .selection
    /// Быстрая сумма, «Отменить».
    static let light: SensoryFeedback = .impact(weight: .light, intensity: 0.7)
    /// «Ещё одна», долгое нажатие.
    static let medium: SensoryFeedback = .impact(weight: .medium)
    /// «Сохранить».
    static let success: SensoryFeedback = .success
    /// «Сохранить» без суммы (вместе с тряской).
    static let error: SensoryFeedback = .error
    /// Удаление категории.
    static let warning: SensoryFeedback = .warning
}

extension View {
    /// Анимация токена; при Reduce Motion — `Motion.reduced`.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }

    /// Тряска по смене `trigger` (design.json → error-shake). При Reduce Motion не трясёт.
    func errorShake(trigger: some Hashable) -> some View {
        modifier(ErrorShakeModifier(trigger: AnyHashable(trigger)))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Motion.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}

private struct ErrorShakeModifier: ViewModifier {
    let trigger: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            shaking(content)
        }
    }

    private func shaking(_ content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            let offsets = Motion.errorShakeOffsets.dropFirst()
            let step = Motion.errorShakeDuration / Double(offsets.count)
            KeyframeTrack {
                for offset in offsets {
                    LinearKeyframe(offset, duration: step)
                }
            }
        }
    }
}

/// Отклик нажатия масштабом для сплошных предметов (плитки, строки, кружки). Не для стекла с `.interactive()`.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = Motion.PressScale.tile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Нажатие масштабом: `.pressable()` — плитка, `.pressable(Motion.PressScale.row)` — строка.
    static func pressable(_ scale: CGFloat = Motion.PressScale.tile) -> PressableButtonStyle {
        PressableButtonStyle(scale: scale)
    }
}
