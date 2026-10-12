import SwiftUI

/// Рецепты стекла (design.json → glass, §3.4) поверх системного Liquid Glass. CSS-рецепты — только эталон
/// для сверки: тени, блики, тёмный вариант и Reduce Transparency система делает сама.
/// Стекло — только управление и навигация; контент (лист, строки, клетки, визуализации) сплошной.
/// Ряды стекла (пара ‹ ›, быстрые суммы, дата + заметка, таб-бар + «+») — внутри `GlassEffectContainer`.
nonisolated enum GlassRecipe {
    /// `glass`: хром — таб-бар, кнопки шапки, сегмент, тосты, пилюля пакета.
    case chrome
    /// `glass-in`: стекло на бумажном листе — липкий заголовок дня, «Записать на …», поиск.
    case inContent
    /// `glass-k`: мелкие клавиши — быстрые суммы, дата, заметка, чипы периодов. Свой отклик нажатия.
    case key
    /// `lens`: только выбранный день в календаре. Под `.clear` нужна подложка — клетка heat.
    case lens

    var glass: Glass {
        switch self {
        case .chrome, .inContent: .regular
        case .key: .regular.interactive()
        case .lens: .clear
        }
    }
}

extension View {
    /// Стекло по рецепту в форме капсулы.
    func glass(_ recipe: GlassRecipe = .chrome) -> some View {
        glassEffect(recipe.glass, in: .capsule)
    }

    /// Стекло по рецепту в произвольной форме.
    func glass(_ recipe: GlassRecipe, in shape: some Shape) -> some View {
        glassEffect(recipe.glass, in: shape)
    }

    /// Линза выбранного дня (r 12) поверх клетки календаря.
    func glassLens() -> some View {
        glassEffect(GlassRecipe.lens.glass, in: .rect(cornerRadius: Theme.Radius.lens, style: .continuous))
    }

    /// `pro`: одно главное действие на экран («Сохранить», «+», «Готово», «Показать …»).
    /// Графит 88 % в светлой, night-ink 92 % в тёмной; подпись — onInk.
    func prominentGlassButtonStyle() -> some View {
        buttonStyle(.glassProminent)
            .tint(Theme.prominent)
            .foregroundStyle(Theme.onInk)
    }

    /// Обычная стеклянная кнопка: текст графитом (night-ink в тёмной).
    func glassButtonStyle() -> some View {
        buttonStyle(.glass)
            .foregroundStyle(Theme.ink)
    }
}
