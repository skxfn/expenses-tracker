import SwiftUI

/// Клетка дня (DESIGN.md → Calendar): 52, r 6, число SF 13/600, сумма SF 13/500, заливка heat-0…4.
/// Будущий день — без клетки, число серым. Сегодня — стеклянная линза поверх клетки.
/// Выбранный не-сегодняшний день — обводка 2 графитом со смещением 2 (как фокус).
struct CalendarDayCell: View {
    let day: CalendarModel.Day
    let number: String
    let amount: String?
    let isSelected: Bool

    /// «12 тыс» и «1 234» на грани ширины клетки (copy.json → risk); на крупном тексте сжимаются сильнее,
    /// полная сумма — в Large Content Viewer и VoiceOver.
    static let amountMinimumScale: CGFloat = 0.5

    var body: some View {
        if !day.isSelectable {
            content(digits: Theme.tertiary)
        } else {
            content(digits: Theme.heatDigits(day.level))
                .opacity(day.isToday ? 0 : 1)
                .background { cell }
                .overlay { selectionOutline }
                .overlay {
                    if day.isToday {
                        TodayLens(number: number, amount: amount, level: day.level)
                            .padding(-CalendarMetrics.lensOutset)
                    }
                }
        }
    }

    private func content(digits: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: number)
                .typeStyle(.footnoteStrong)
            Spacer(minLength: 0)
            if let amount {
                Text(verbatim: amount)
                    .typeStyle(.calendarCellAmount)
                    .minimumScaleFactor(Self.amountMinimumScale)
            }
        }
        .foregroundStyle(digits)
        .lineLimit(1)
        .padding(CalendarMetrics.cellPadding)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.calendarCell, alignment: .leading)
    }

    private var cell: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
        return shape
            .fill(Theme.heat(day.level))
            .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
            .paperShadow(Tokens.Shadow.swatchRest)
    }

    @ViewBuilder
    private var selectionOutline: some View {
        if isSelected && !day.isToday {
            let outset = CalendarMetrics.selectionOffset + CalendarMetrics.selectionLineWidth
            RoundedRectangle(cornerRadius: Theme.Radius.swatch + outset, style: .continuous)
                .strokeBorder(Theme.ink, lineWidth: CalendarMetrics.selectionLineWidth)
                .padding(-outset)
                .allowsHitTesting(false)
        }
    }
}

/// Линза «сегодня» (`lens`, §3.4): прозрачное стекло r 12 с выступом 6 над клеткой heat, цифры крупнее,
/// дата подчёркнута (2). Цвет цифр — по ступени клетки: на heat-4 светлые (design.json → openQuestions).
private struct TodayLens: View {
    let number: String
    let amount: String?
    let level: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lens, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: number)
                .typeStyle(.calendarLensNumber)
                .padding(.bottom, CalendarMetrics.lensUnderlineGap + CalendarMetrics.lensUnderline)
                .overlay(alignment: .bottom) {
                    Rectangle().frame(height: CalendarMetrics.lensUnderline)
                }
            Spacer(minLength: 0)
            if let amount {
                Text(verbatim: amount)
                    .typeStyle(.calendarLensAmount)
                    .minimumScaleFactor(CalendarDayCell.amountMinimumScale)
            }
        }
        .foregroundStyle(Theme.heatDigits(level))
        .lineLimit(1)
        .padding(CalendarMetrics.lensPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // В тёмной теме линза чуть затемняет центр (DESIGN.md → Calendar, `lens-dark`).
        .background(.black.opacity(colorScheme == .dark ? CalendarMetrics.lensNightDimming : 0), in: shape)
        .glassEffect(GlassRecipe.lens.glass.tint(Theme.heat(level).opacity(CalendarMetrics.lensTintOpacity)), in: shape)
        .background { LensShadow() }
        .allowsHitTesting(false)
    }
}
