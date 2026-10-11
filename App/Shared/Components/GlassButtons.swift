import SwiftUI

/// Стеклянная кнопка-капсула (DESIGN.md → Buttons): 50 — действия («Ещё одна», «Удалить», «Сохранить»),
/// 44 — клавиши и чипы («К последней трате», «+ Заметка»). Стекло системное с `.interactive()` —
/// у него свой отклик нажатия, масштаб `press` не добавляется.
struct GlassCapsuleButtonStyle: ButtonStyle {
    enum Kind {
        /// Обычное стекло, текст ink.
        case glass
        /// Стекло, текст и иконка destructive.
        case destructive
        /// `pro`: одно главное действие на экран — графит 88 % (night-ink 92 % в тёмной), текст onInk.
        case prominent
    }

    var kind: Kind = .glass
    var height: CGFloat = Theme.Size.actionButton
    /// Растягиваться на ширину, которую даёт родитель (пара «Ещё одна | Сохранить»).
    var expands = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(height < Theme.Size.actionButton ? .callout : .headline)
            .foregroundStyle(foreground)
            .opacity(isEnabled ? 1 : Theme.disabledArrowOpacity)
            .lineLimit(1)
            // Длинная подпись («Записать на 30 сентября», крупный шрифт) ужимается, а не обрезается.
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: height)
            .contentShape(Capsule())
            .glassEffect(glass, in: .capsule)
    }

    private var glass: Glass {
        switch kind {
        case .glass, .destructive: .regular.interactive()
        case .prominent: .regular.tint(Theme.prominent).interactive()
        }
    }

    private var foreground: Color {
        switch kind {
        case .glass: Theme.ink
        case .destructive: Theme.destructive
        case .prominent: Theme.onInk
        }
    }
}

/// Круглая стеклянная кнопка-иконка: 44 — ‹ › ⚙ в шапке; 62 prominent — круг «+» у таб-бара.
struct GlassCircleButtonStyle: ButtonStyle {
    var diameter: CGFloat = Theme.Size.iconButton
    var prominent = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: diameter * 0.4, weight: prominent ? .regular : .medium))
            .foregroundStyle(prominent ? Theme.onInk : Theme.ink)
            .opacity(isEnabled ? 1 : Theme.disabledArrowOpacity)
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .glassEffect(prominent ? .regular.tint(Theme.prominent).interactive() : .regular.interactive(), in: .circle)
    }
}

extension ButtonStyle where Self == GlassCapsuleButtonStyle {
    static func glassCapsule(
        _ kind: GlassCapsuleButtonStyle.Kind = .glass,
        height: CGFloat = Theme.Size.actionButton,
        expands: Bool = true
    ) -> GlassCapsuleButtonStyle {
        GlassCapsuleButtonStyle(kind: kind, height: height, expands: expands)
    }
}

extension ButtonStyle where Self == GlassCircleButtonStyle {
    static func glassCircle(diameter: CGFloat = Theme.Size.iconButton, prominent: Bool = false) -> GlassCircleButtonStyle {
        GlassCircleButtonStyle(diameter: diameter, prominent: prominent)
    }
}

/// Пара ‹ › в одной стеклянной капсуле (шапка: шаг периода). Неактивная стрелка — ink 30 %.
struct GlassStepperPair: View {
    let previousLabel: LocalizedStringKey
    let nextLabel: LocalizedStringKey
    var canGoPrevious = true
    var canGoNext = true
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: previousLabel, isEnabled: canGoPrevious, action: onPrevious)
            arrow("chevron.right", label: nextLabel, isEnabled: canGoNext, action: onNext)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func arrow(_ symbol: String, label: LocalizedStringKey, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .opacity(isEnabled ? 1 : Theme.disabledArrowOpacity)
                .frame(width: Theme.Size.iconButton, height: Theme.Size.iconButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

#if DEBUG
#Preview("Кнопки") {
    ThemePreview {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Spacer()
                GlassStepperPair(previousLabel: "Назад", nextLabel: "Вперёд", canGoNext: false, onPrevious: {}, onNext: {})
                Button("Настройки", systemImage: "gearshape") {}
                    .buttonStyle(.glassCircle())
            }
            HStack(spacing: Theme.Spacing.md) {
                Button("Ещё одна") {}
                    .buttonStyle(.glassCapsule())
                Button("Сохранить") {}
                    .buttonStyle(.glassCapsule(.prominent))
            }
            HStack(spacing: Theme.Spacing.md) {
                Button("Удалить", systemImage: "trash") {}
                    .buttonStyle(.glassCapsule(.destructive))
                Button("Новая трата", systemImage: "plus") {}
                    .buttonStyle(.glassCircle(diameter: Theme.Size.addButton, prominent: true))
            }
        }
    }
}
#endif
