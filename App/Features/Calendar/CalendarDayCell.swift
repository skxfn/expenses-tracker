import SwiftUI

/// Клетка дня (DESIGN.md → Calendar): 52, r 6, число SF 13/600, сумма SF 13/500, заливка heat-0…4.
/// Будущий день — без клетки, число серым. Выбранный день — стеклянная линза поверх клетки (`DayLens`, рисует
/// `CalendarGrid` слоем над сеткой), цифры клетки под ней гаснут. Сегодня — число подчёркнуто (2), и в клетке, и в линзе.
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
                .opacity(isSelected ? 0 : 1)
                .motion(Motion.morph, value: isSelected)
                .background { cell }
        }
    }

    private func content(digits: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: number)
                .typeStyle(.footnoteStrong)
                // Подчёркивание поверх, а не отступом: раскладка клетки «сегодня» та же, что у соседних.
                .overlay(alignment: .bottom) {
                    if day.isToday {
                        Rectangle()
                            .frame(height: CalendarMetrics.lensUnderline)
                            .offset(y: CalendarMetrics.lensUnderlineGap + CalendarMetrics.lensUnderline)
                    }
                }
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
}

/// Линза выбранного дня (`lens`, §3.4): прозрачное стекло r 12 с выступом 6 над клеткой heat, цифры крупнее;
/// у «сегодня» дата подчёркнута (2). Цвет цифр — по ступени клетки: на heat-4 светлые (design.json → openQuestions).
struct DayLens: View {
    let number: String
    let amount: String?
    let level: Int
    let isToday: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lens, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: number)
                .typeStyle(.calendarLensNumber)
                .padding(.bottom, CalendarMetrics.lensUnderlineGap + CalendarMetrics.lensUnderline)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .frame(height: CalendarMetrics.lensUnderline)
                        .opacity(isToday ? 1 : 0)
                        .animation(nil, value: isToday)
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
        // Линза везёт цифры нового дня сразу (и подчёркивание): наплыв «12» на «9» в полёте читается как сбой.
        .contentTransition(.identity)
        .padding(CalendarMetrics.lensPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // В тёмной теме линза чуть затемняет центр (DESIGN.md → Calendar, `lens-dark`).
        .background(.black.opacity(colorScheme == .dark ? CalendarMetrics.lensNightDimming : 0), in: shape)
        .glassEffect(GlassRecipe.lens.glass.tint(Theme.heat(level).opacity(CalendarMetrics.lensTintOpacity)), in: shape)
        .background { LensShadow() }
        .allowsHitTesting(false)
    }
}
