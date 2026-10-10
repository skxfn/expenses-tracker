import SwiftUI
import ExpenseCore

/// Роли тона «Гуаши» для UI (DESIGN.md → «Правило тинта», design.json → darkTheme.gouache, icons.dark).
/// Насыщенный тон — только мелким (иконка, штрих, сегмент, образец, плитка); площади крупнее плашки 36 — `area`.
nonisolated extension GouacheTone {
    /// Основной тон: светлый в светлой теме, ночной в тёмной (отличается только у Пиона).
    var main: Color { Color(light: tokens.main, dark: tokens.mainNight) }
    var tint: Color { Color(rgb: tokens.tint) }
    var deep: Color { Color(rgb: tokens.deep) }
    var darktint: Color { Color(rgb: tokens.darktint) }

    /// Площадь: плашка, невыбранный образец, аура, фон штриховки. Свет — tint, ночь — darktint.
    var area: Color { Color(light: tokens.tint, dark: tokens.darktint) }
    /// Иконка или текст на `area`. Свет — deep, ночь — tint.
    var onArea: Color { Color(light: tokens.deep, dark: tokens.tint) }
    /// Подпись на основном тоне: графит или бумага по тону, в тёмной теме не инвертируется.
    var labelOnMain: Color { Color(rgb: tokens.labelOnMain) }

    /// Штриховка «без подкатегории»: полоса основным тоном по `area` (design.json → hatch).
    var hatchStripe: Color { main }
    var hatchGround: Color { area }

    // MARK: Ступени подкатегорий

    /// Цвет ступени `step` (0 — основной тон; ступень даёт Core: `SubcategoryShades.step(of:)`).
    /// Свет — `subcategoryShades` с повтором (§8 п. 9), ночь — `subcategoryShadesDark`.
    func shade(_ step: Int) -> Color {
        let step = GouacheShades.normalized(step)
        return Color(
            light: tokens.shadesLight[GouacheShades.lightIndex(step, count: tokens.shadesLight.count)],
            dark: tokens.shadesDark[min(step, tokens.shadesDark.count - 1)]
        )
    }

    /// Подпись на ступени `step`: на первой — `labelOnMain`; дальше в светлой deep или бумага по контрасту,
    /// в тёмной — night-ink.
    func labelOnShade(_ step: Int) -> Color {
        let step = GouacheShades.normalized(step)
        return Color(
            light: tokens.labelsLight[GouacheShades.lightIndex(step, count: tokens.labelsLight.count)],
            dark: tokens.labelsDark[min(step, tokens.labelsDark.count - 1)]
        )
    }
}

/// Правило ступеней в одном месте (§8 п. 9: «до ответа дизайнера — 3 светлые ступени и повтор с 4-й»).
nonisolated enum GouacheShades {
    /// Ступень 0…`SubcategoryShades.stepCount - 1` для любого целого.
    static func normalized(_ step: Int) -> Int {
        let count = SubcategoryShades.stepCount
        return ((step % count) + count) % count
    }

    /// Индекс в светлой таблице: ступени 4 и 5 повторяют 1 и 2, пока в design.json только 3 значения.
    static func lightIndex(_ step: Int, count: Int) -> Int {
        step % count
    }
}

/// Цвета категории для компонентов: тон «Гуаши» или нейтраль «Без категории».
/// «Без категории» (§8 п. 10) — вне «Гуаши»: плашка separator, иконка secondary. Выбор — только здесь.
nonisolated enum CategoryPaint {
    /// Иконка «Без категории» (MingCute; в макетах не задана — выбор при внедрении).
    static let uncategorizedIconName = "question-fill"

    static func area(_ tone: GouacheTone?) -> Color { tone?.area ?? Theme.separator }
    static func onArea(_ tone: GouacheTone?) -> Color { tone?.onArea ?? Theme.secondary }
    static func main(_ tone: GouacheTone?) -> Color { tone?.main ?? Theme.graphic }
    /// Иконка на основном тоне — paper-surface в обеих темах (выбранный образец, раскрытая категория).
    static func onMain(_ tone: GouacheTone?) -> Color { Theme.paper }
    /// Тень выбранного образца: deep категории в светлой теме.
    static func shadow(_ tone: GouacheTone?) -> Color { tone?.deep ?? Theme.graphite }
}
