import SwiftUI

/// Размеры календаря из DESIGN.md → Calendar и макета 09, которых нет в общих токенах.
nonisolated enum CalendarMetrics {
    /// Зазор сетки (DESIGN.md: 4).
    static let gridGap = Theme.Spacing.xs
    /// Внутренние отступы клетки (`calendar-cell` → padding 6 7 7).
    static let cellPadding = EdgeInsets(top: 6, leading: 7, bottom: 7, trailing: 7)
    /// Выступ линзы «сегодня» за клетку и её отступы (`.ds-lens`: inset −6, padding 9 12 11).
    static let lensOutset: CGFloat = 6
    static let lensPadding = EdgeInsets(top: 9, leading: 12, bottom: 11, trailing: 12)
    /// Тинт линзы цветом клетки: прозрачное стекло на светлом белит, и ступень heat под ним теряется.
    static let lensTintOpacity: Double = 0.6
    /// Затемнение центра линзы в тёмной теме (`lens-dark`: чёрный .12 в середине градиента).
    static let lensNightDimming: Double = 0.12
    /// Подчёркивание даты в линзе: 2 и отступ от числа.
    static let lensUnderline: CGFloat = 2
    static let lensUnderlineGap: CGFloat = 1
    /// Обводка выбранного дня — как фокус: 2 со смещением 2 (INTEGRATION §2.2).
    static let selectionLineWidth: CGFloat = 2
    static let selectionOffset: CGFloat = 2
    /// Капсула шкалы 44×20 (DESIGN.md); радиус по макету 09 — 4.
    static let legendItemWidth: CGFloat = 44
    static let legendItemHeight: CGFloat = 20
    static let legendItemRadius: CGFloat = 4
    /// Горизонтальный свайп по сетке, который листает месяц.
    static let swipeDistance: CGFloat = 50
}

nonisolated extension TypeStyle {
    /// Сумма в клетке: SF 13/500 (INTEGRATION §8 п. 6 — не Unbounded).
    static let calendarCellAmount = TypeStyle(
        font: .system(.footnote).weight(.medium), size: 13, textStyle: .footnote, trackingEm: 0, tabularDigits: true
    )
    /// Число в линзе «сегодня»: SF 16/700 — линза увеличивает клетку (`.ds-lens b`).
    static let calendarLensNumber = TypeStyle(
        font: .system(.callout).weight(.bold), size: 16, textStyle: .callout, trackingEm: 0, tabularDigits: true
    )
    /// Сумма в линзе: SF 16/500 (в макете — Unbounded 16; по §8 п. 6 суммы клетки — SF).
    static let calendarLensAmount = TypeStyle(
        font: .system(.callout).weight(.medium), size: 16, textStyle: .callout, trackingEm: 0, tabularDigits: true
    )
    /// Сумма выбранного дня рядом с Title: Unbounded 500 22 (DESIGN.md → Typography, Title).
    static let calendarDayAmount = TypeStyle(
        font: .custom(UnboundedFont.Weight.medium.postScriptName, size: 22, relativeTo: .title2),
        size: 22, textStyle: .title2, trackingEm: 0, tabularDigits: true
    )
}

/// Тень линзы «сегодня» (`.ds-lens`: 0 10 22 / 0 2 5, тёплая .22 / .14; в тёмной — чёрная .5 / .4).
/// Только снаружи формы: под `.clear`-стеклом заливки быть не должно, иначе стекло покажет её, а не клетку.
/// Тень и делает линзу читаемой на светлых клетках, где прозрачное стекло почти не видно.
struct LensShadow: View {
    private static let far = ShadowToken(x: 0, y: 10, blur: 22, rgb: Tokens.Paper.graphite, lightAlpha: 0.22, darkAlpha: 0.5)
    private static let near = ShadowToken(x: 0, y: 2, blur: 5, rgb: Tokens.Paper.graphite, lightAlpha: 0.14, darkAlpha: 0.4)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lens, style: .continuous)
        shape
            .fill(.black)
            .paperShadow(Self.far)
            .paperShadow(Self.near)
            .mask {
                ZStack {
                    Rectangle().padding(-Self.far.blur * 2)
                    shape.blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
