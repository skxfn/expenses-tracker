import SwiftUI

/// Клетка дня (DESIGN.md → Calendar): 52, r 6, число SF 13/600, сумма SF 13/500, заливка heat-0…4.
/// Будущий день — без клетки, число серым. Выбранный день — стеклянная линза поверх клетки (`DayLens`, рисует
/// `CalendarGrid` слоем над сеткой): цифры клетки гаснут, когда линза села на неё, и проявляются, как только
/// линза взлетела. Сегодня — число подчёркнуто (2), и в клетке, и в линзе.
struct CalendarDayCell: View {
    let day: CalendarModel.Day
    let number: String
    let amount: String?
    /// Линза стоит над клеткой и показывает её цифры.
    let isUnderLens: Bool

    /// «12 тыс» и «1 234» на грани ширины клетки (copy.json → risk); на крупном тексте сжимаются сильнее,
    /// полная сумма — в Large Content Viewer и VoiceOver.
    static let amountMinimumScale: CGFloat = 0.5

    var body: some View {
        if !day.isSelectable {
            content(digits: Theme.tertiary)
        } else {
            content(digits: Theme.heatDigits(day.level))
                .opacity(isUnderLens ? 0 : 1)
                // Линза взлетела — цифры на месте сразу; села — гаснут вместе с проявлением её цифр.
                .animation(isUnderLens ? LensMotion.digitsIn : nil, value: isUnderLens)
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
/// Reduce Transparency — сплошная заливка цветом клетки вместо стекла.
struct DayLens: View {
    /// Цифры дня, над которым линза села (`level`, `isToday` — его же).
    let number: String
    let amount: String?
    let level: Int
    let isToday: Bool
    /// Ступень клетки под линзой (выбранного дня) — тинт стекла.
    let tintLevel: Int
    /// Цифры видны у севшей линзы; в полёте их нет — сквозь стекло видны цифры клеток.
    let showsDigits: Bool
    /// Заливка тинтом: 1 — линза стоит, меньше — поднята и прозрачнее.
    private(set) var fill: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
        // Цифры сменяются, пока скрыты: наплыв «12» на «9» читается как сбой.
        .contentTransition(.identity)
        .opacity(showsDigits ? 1 : 0)
        .animation(showsDigits ? LensMotion.digitsIn : nil, value: showsDigits)
        .padding(CalendarMetrics.lensPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(LensSurface(
            shape: shape, tint: Theme.heat(tintLevel), fill: fill, isSolid: reduceTransparency, isDark: colorScheme == .dark
        ))
        .background { LensShadow() }
        .allowsHitTesting(false)
    }

    /// Та же линза с другой заливкой (кадр подъёма).
    func filled(_ fill: Double) -> DayLens {
        var lens = self
        lens.fill = fill
        return lens
    }
}

/// Поверхность линзы: стекло `.clear` с тинтом клетки (доля — `fill`) или сплошная заливка при Reduce Transparency.
private struct LensSurface: ViewModifier {
    let shape: RoundedRectangle
    let tint: Color
    let fill: Double
    let isSolid: Bool
    let isDark: Bool

    func body(content: Content) -> some View {
        if isSolid {
            content
                .background(tint, in: shape)
                .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
        } else {
            content
                // В тёмной теме линза чуть затемняет центр (DESIGN.md → Calendar, `lens-dark`).
                .background(.black.opacity(isDark ? CalendarMetrics.lensNightDimming * fill : 0), in: shape)
                .glassEffect(GlassRecipe.lens.glass.tint(tint.opacity(CalendarMetrics.lensTintOpacity * fill)), in: shape)
        }
    }
}
