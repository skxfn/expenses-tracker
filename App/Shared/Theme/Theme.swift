import SwiftUI
import UIKit

extension Color {
    /// Цвет из `0xRRGGBB` (sRGB, непрозрачный).
    nonisolated init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// Цвет, который следует системной теме: `light` в светлой, `dark` в тёмной.
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Полупрозрачный цвет по теме.
    nonisolated init(light: UInt32, lightAlpha: Double, dark: UInt32, darkAlpha: Double) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        })
    }

    nonisolated init(_ pair: TokenPair) {
        self.init(light: pair.light, dark: pair.dark)
    }
}

extension UIColor {
    nonisolated convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Семантические цвета, радиусы, отступы и размеры дизайна «Образцы».
/// Значения — из `Tokens.generated.swift` (scripts/gen_tokens.py); здесь только роли.
/// Тема следует системе: переключателя в макетах нет.
nonisolated enum Theme {
    // MARK: Нейтрали

    /// Фон экрана (под аурой и стеклом).
    static let canvas = Color(Tokens.Neutral.canvas)
    /// Фон шита.
    static let canvasElevated = Color(Tokens.Neutral.canvasElevated)
    /// Лист ленты, группы, поля, карточки — и внутри шитов.
    static let surface = Color(Tokens.Neutral.surface)
    /// Основной текст, главное действие, фокус.
    static let ink = Color(Tokens.Neutral.ink)
    /// Подписи, «Br», неактивные сегменты.
    static let secondary = Color(Tokens.Neutral.secondary)
    /// Только неактивное и будущее (на canvas для текста не годится).
    static let tertiary = Color(Tokens.Neutral.tertiary)
    /// Плейсхолдер на стекле.
    static let placeholder = Color(Tokens.Neutral.placeholder)
    /// Шевроны, контур чекбокса, прошлые столбики (≥ 3:1).
    static let graphic = Color(Tokens.Neutral.graphic)
    /// Волосяные линии 0,5, контур «Все».
    static let separator = Color(Tokens.Neutral.separator)
    /// Текст и иконка «Удалить».
    static let destructive = Color(Tokens.Neutral.destructive)
    /// Текст и иконка на главном действии (prominent).
    static let onInk = Color(Tokens.Neutral.onInk)
    /// Выглядывающий родительский шит — только если рисуем его сами.
    static let sheetBehind = Color(Tokens.Neutral.sheetBehind)

    /// paper-surface в обеих темах: иконка и светлая подпись на основных тонах «Гуаши» не инвертируются.
    static let paper = Color(rgb: Tokens.Paper.surface)
    /// Графит в обеих темах: тёмная подпись на основных тонах «Гуаши».
    static let graphite = Color(rgb: Tokens.Paper.graphite)

    /// Неактивная стрелка ‹ › (DESIGN.md: графит 28 %, в тёмной — ink 30 %).
    static let disabledArrowOpacity: Double = 0.3

    // MARK: Полупрозрачные роли (design.json → glass, shadows)

    /// Активная пилюля сегмента: белая 92 % (`segment-period` → `.on`) / rgba(255,250,244,.16) (`segment-active-dark`).
    static let segmentPill = Color(
        light: 0xFFFFFF, lightAlpha: 0.92,
        dark: 0xFFFAF4, darkAlpha: 0.16
    )
    /// Главное действие (`pro`): графит 88 % под стеклом / night-ink 92 % (`pro-dark`) — tint prominent-стекла.
    static let prominent = Color(
        light: Tokens.Neutral.ink.light, lightAlpha: 0.88,
        dark: Tokens.Neutral.ink.dark, darkAlpha: 0.92
    )
    /// Активная вкладка таб-бара: графит 8 % / ink 10 % (`tab-active-dark`).
    static let tabPill = Color(
        light: Tokens.Neutral.ink.light, lightAlpha: 0.08,
        dark: Tokens.Neutral.ink.dark, darkAlpha: 0.10
    )
    /// Волосяной контур бумажных предметов (группа, образец): графит 6 % / белый 6 % (shadows → dark-rule).
    static let hairlineOutline = Color(
        light: Tokens.Paper.graphite, lightAlpha: 0.06,
        dark: 0xFFFFFF, darkAlpha: 0.06
    )
    /// Светлая линия по верхнему краю листа — только в тёмной (`sheet-dark`: inset 0 .5px rgba(255,255,255,.07)).
    static let sheetHighlight = Color(
        light: 0xFFFFFF, lightAlpha: 0,
        dark: 0xFFFFFF, darkAlpha: 0.07
    )

    // MARK: Шкала heat

    /// Число ступеней шкалы heat.
    static let heatLevels = Tokens.heat.count

    /// Заливка клетки календаря и тепловой карты, `level` 0…4 (зажимается в диапазон).
    static func heat(_ level: Int) -> Color {
        Color(Tokens.heat[clampedHeat(level)])
    }

    /// Цифры на клетке: ink на 0–3, onInk на 4 (в обеих темах; design.json → darkTheme.heat.digits).
    static func heatDigits(_ level: Int) -> Color {
        clampedHeat(level) == heatLevels - 1 ? onInk : ink
    }

    private static func clampedHeat(_ level: Int) -> Int {
        min(max(level, 0), heatLevels - 1)
    }

    // MARK: Формы и отступы

    /// Радиусы (DESIGN.md → rounded; §3.5).
    enum Radius {
        /// Внутренние углы соседних подкатегорий в плитке.
        static let chipInner = Tokens.Radius.chipInner
        /// Образец 46×60, клетка календаря.
        static let swatch = Tokens.Radius.swatch
        /// Плитка treemap.
        static let tile = Tokens.Radius.tile
        /// Плашка иконки 36.
        static let plaque = Tokens.Radius.plaque
        /// Крупная плашка 52 (design.json → icons.plaque).
        static let plaqueLarge: CGFloat = 15
        /// Линза «сегодня».
        static let lens = Tokens.Radius.lens
        /// Поле ввода 52.
        static let field = Tokens.Radius.field
        /// Группа настроек.
        static let group = Tokens.Radius.group
        /// Верх бумажного листа ленты и календаря.
        static let sheetPanel = Tokens.Radius.sheetPanel
        // Радиус шита — системный (§8 п. 6): `presentationCornerRadius` не задавать.
    }

    /// Отступы 4 / 8 / 12 / 16 / 20, поля экрана 16.
    enum Spacing {
        static let xs = Tokens.Spacing.xs
        static let sm = Tokens.Spacing.sm
        static let md = Tokens.Spacing.md
        static let lg = Tokens.Spacing.lg
        static let xl = Tokens.Spacing.xl
        /// Боковые поля экрана.
        static let screen = Tokens.Spacing.lg
        /// Зазор между категориями (плитки).
        static let categoryGap = Tokens.Spacing.tileGap
        /// Зазор между подкатегориями внутри категории.
        static let subcategoryGap: CGFloat = 1
        /// Зазор между сегментами кольца и полосы.
        static let segmentGap = Tokens.Spacing.hairline
    }

    /// Размеры компонентов в pt при размере текста по умолчанию.
    enum Size {
        /// Стеклянная кнопка-иконка (‹ › ⚙ ✕), цель касания.
        static let iconButton = Tokens.Size.iconButtonGlass
        /// Кнопка действия («Сохранить», «Ещё одна», «Удалить»).
        static let actionButton = Tokens.Size.buttonGlassHeight
        /// Таб-бар и круг «+».
        static let tabBar = Tokens.Size.tabBarHeight
        static let addButton = Tokens.Size.tabBarAdd
        /// Сегмент периода и его активная пилюля.
        static let segment = Tokens.Size.segmentPeriodHeight
        static let segmentPill = Tokens.Size.segmentPeriodActiveHeight
        /// Липкий заголовок дня, внутренние пилюли.
        static let dayHeader = Tokens.Size.dayHeaderHeight
        /// Строка ленты.
        static let feedRow = Tokens.Size.feedRowHeight
        /// Строка «Полос».
        static let stripRow = Tokens.Size.stripRowHeight
        /// Быстрая сумма, чипы периодов, поиск.
        static let chip = Tokens.Size.quickSumChipHeight
        /// Образец категории.
        static let swatchWidth = Tokens.Size.swatchChipWidth
        static let swatchHeight = Tokens.Size.swatchChipHeight
        /// Подъём выбранного образца (DESIGN.md → Category Swatches).
        static let swatchLift: CGFloat = 8
        /// Плашка иконки и иконка в ней (design.json → icons.plaque).
        static let plaque = Tokens.Size.categoryPlaque
        static let plaqueIcon: CGFloat = 20
        static let plaqueLarge: CGFloat = 52
        static let plaqueLargeIcon: CGFloat = 26
        /// Иконка в образце.
        static let swatchIcon: CGFloat = 22
        /// Поле ввода.
        static let field = Tokens.Size.textFieldHeight
        /// Клетка календаря.
        static let calendarCell = Tokens.Size.calendarCellHeight
        /// Волосяная линия.
        static let hairline: CGFloat = 0.5
        /// Переключатель «Обозначение» (знак | BYN) в строке настроек, макет `12-settings`.
        static let symbolStylePicker: CGFloat = 120
    }
}

// MARK: - Тени

extension View {
    /// Тень бумажного предмета (лист, образец, пилюля сегмента): тёплая в светлой, чёрная и плотнее в тёмной.
    func paperShadow(_ token: ShadowToken) -> some View {
        modifier(PaperShadow(token: token))
    }
}

private struct PaperShadow: ViewModifier {
    let token: ShadowToken
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let color = isDark ? Color.black : Color(rgb: token.rgb)
        content.shadow(
            color: color.opacity(isDark ? token.darkAlpha : token.lightAlpha),
            radius: token.blur / 2,
            x: token.x,
            y: token.y
        )
    }
}
