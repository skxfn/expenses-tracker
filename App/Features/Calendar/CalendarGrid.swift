import SwiftUI
import ExpenseCore

/// Сетка месяца: дни недели с `calendar.firstWeekday` и 4–6 недель по 7 клеток с зазором 4.
/// Свайп влево / вправо листает месяц; смена месяца — растворение (без полёта: и при Reduce Motion то же).
/// Линза выбранного дня рисуется слоем поверх сетки по рамке клетки (`SelectedCellAnchorKey`): выступ линзы должен
/// лежать поверх соседей, а `zIndex` у клетки уводил её в конец порядка VoiceOver (после 31-го).
/// Выбор другого дня — линза поднимается и перелетает к нему (`SelectionLens`, `LensMotion`); при Reduce Motion —
/// гаснет и проявляется. Касание выбранного дня приподнимает линзу, остальные клетки при нажатии сжимаются.
struct CalendarGrid: View {
    let model: CalendarModel
    let strings: CalendarStrings
    let onSelect: (Date) -> Void
    let onAdd: (Date) -> Void
    let onSwipe: (_ forward: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Полёт линзы к выбранному дню; `nil` — линза стоит над ним.
    @State private var lensFlight: LensFlight?
    /// Клетка под пальцем.
    @State private var pressedDay: Date?

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            weekdays
            ZStack {
                weeks
                    .overlayPreferenceValue(SelectedCellAnchorKey.self) { anchor in
                        selectionLens(anchor)
                    }
                    .id(model.month.start)
                    .transition(.opacity)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: strings.gridAccessibility(model.month)))
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        // Другой месяц — без полёта: линза новой сетки сразу над выбранным днём.
        .onChange(of: model.month.start) { lensFlight = nil }
        // Посадка: цифры выбранного дня — после неё; новый выбор в полёте откладывает её.
        .task(id: [model.selectedDay, lensFlight?.takeoff]) {
            guard lensFlight != nil else { return }
            try? await Task.sleep(for: LensMotion.cruise)
            guard !Task.isCancelled else { return }
            lensFlight?.isLanding = true
            try? await Task.sleep(for: LensMotion.landing - LensMotion.cruise)
            guard !Task.isCancelled else { return }
            lensFlight = nil
        }
    }

    /// Выбор касанием: линза взлетает (Reduce Motion — без полёта, сразу над новым днём).
    private func liftOff(to date: Date) {
        guard date != model.selectedDay, !reduceMotion else { return }
        if lensFlight == nil {
            lensFlight = LensFlight(takeoff: model.selectedDay)
        } else {
            lensFlight?.isLanding = false
        }
    }

    private var weekdays: some View {
        HStack(spacing: CalendarMetrics.gridGap) {
            ForEach(model.month.weekdays, id: \.self) { weekday in
                Text(LocalizedStringKey(Self.weekdayKey(weekday)))
                    .typeStyle(.footnoteStrong)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    // «Mon», «Wed» на крупном тексте шире колонки 49: уменьшаются, а не «M…».
                    .minimumScaleFactor(Self.weekdayMinimumScale)
                    .padding(.leading, CalendarMetrics.cellPadding.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }

    private var weeks: some View {
        weeksGrid(dayView)
    }

    /// Копия клеток без кнопок — то, что линза в полёте показывает увеличенным (`SelectionLens`).
    /// Цифры в ней видны всегда: при посадке окно линзы гаснет вместе с ними, пока проявляются цифры линзы.
    private var weeksBackdrop: some View {
        weeksGrid { date in
            cell(date, isUnderLens: false)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func weeksGrid<Day: View>(_ day: @escaping (Date) -> Day) -> some View {
        Grid(horizontalSpacing: CalendarMetrics.gridGap, verticalSpacing: CalendarMetrics.gridGap) {
            ForEach(Array(model.month.weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        if let date {
                            day(date)
                        } else {
                            Color.clear.gridCellUnsizedAxes(.vertical)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ date: Date, isUnderLens: Bool) -> CalendarDayCell {
        let day = model.day(date)
        return CalendarDayCell(
            day: day, number: strings.dayNumber(date), amount: strings.cellAmount(day.totalMinor), isUnderLens: isUnderLens
        )
    }

    @ViewBuilder
    private func dayView(_ date: Date) -> some View {
        let day = model.day(date)
        let isSelected = date == model.selectedDay
        let isPeak = date == model.summary.peakDay
        let amount = strings.cellAmount(day.totalMinor)
        // Цифры клетки гаснут с началом посадки: окно линзы над ней ещё показывает их копию.
        let cell = self.cell(date, isUnderLens: isSelected && (lensFlight?.isLanding ?? true))
        let label = Text(verbatim: strings.dayAccessibility(day, isSelected: isSelected, isPeak: isPeak))

        if day.isSelectable {
            let marksSelection = isSelected && !strings.accessibilityStatesSelection(day, isSelected: isSelected)
            Button {
                liftOff(to: date)
                onSelect(date)
            } label: {
                cell
            }
            .buttonStyle(DayButtonStyle(isSelected: isSelected) { isPressed in
                if isPressed {
                    pressedDay = date
                } else if pressedDay == date {
                    pressedDay = nil
                }
            })
            .simultaneousGesture(
                LongPressGesture(minimumDuration: Self.longPressDuration).onEnded { _ in
                    liftOff(to: date)
                    onAdd(date)
                }
            )
            .anchorPreference(key: SelectedCellAnchorKey.self, value: .bounds) { isSelected ? $0 : nil }
            .accessibilityLabel(label)
            .accessibilityAddTraits(marksSelection ? .isSelected : [])
            .accessibilityAction(named: Text("cal.longPress.a11y")) { onAdd(date) }
            .accessibilityShowsLargeContentViewer {
                Text(verbatim: [strings.dayNumber(date), amount].compactMap { $0 }.joined(separator: " "))
            }
        } else {
            cell
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        }
    }

    /// Линза поверх выбранной клетки с выступом за её края. Только рисунок: касания и VoiceOver — у клетки.
    /// Тинт — по выбранной клетке; в полёте цифр нет (гаснут цифры дня, откуда линза взлетела).
    @ViewBuilder
    private func selectionLens(_ anchor: Anchor<CGRect>?) -> some View {
        if let anchor {
            let selected = model.selected
            let shown = lensFlight.map { model.day($0.takeoff) } ?? selected
            GeometryReader { proxy in
                SelectionLens(
                    rect: proxy[anchor].insetBy(dx: -CalendarMetrics.lensOutset, dy: -CalendarMetrics.lensOutset),
                    canvas: proxy.size,
                    backdrop: weeksBackdrop,
                    date: selected.date,
                    isPressed: pressedDay == selected.date && lensFlight == nil,
                    lens: DayLens(
                        number: strings.dayNumber(shown.date),
                        amount: strings.cellAmount(shown.totalMinor),
                        level: shown.level,
                        isToday: shown.isToday,
                        tintLevel: selected.level,
                        showsDigits: lensFlight == nil
                    )
                )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Горизонтальный свайп: влево — следующий месяц, вправо — предыдущий.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: Theme.Spacing.xl).onEnded { value in
            let dx = value.translation.width
            guard abs(dx) > CalendarMetrics.swipeDistance, abs(dx) > abs(value.translation.height) * 1.5 else { return }
            onSwipe(dx < 0)
        }
    }

    private static let longPressDuration = 0.5
    private static let weekdayMinimumScale: CGFloat = 0.7

    /// Ключ `cal.weekdays.*` по номеру дня недели `Calendar` (1 — воскресенье).
    private static func weekdayKey(_ weekday: Int) -> String {
        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        return "cal.weekdays." + names[(weekday - 1) % names.count]
    }
}

/// Полёт линзы: день, откуда она взлетела (его цифры гаснут в линзе), и началась ли посадка.
private struct LensFlight: Equatable {
    let takeoff: Date
    var isLanding = false
}

/// Нажатие клетки: невыбранная сжимается, как `pressable`; выбранная остаётся на месте — над ней приподнимается
/// линза (`onPressChange` сообщает сетке, какая клетка под пальцем).
private struct DayButtonStyle: ButtonStyle {
    let isSelected: Bool
    let onPressChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !isSelected && !reduceMotion ? Motion.PressScale.tile : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in onPressChange(isPressed) }
    }
}

/// Рамка выбранной клетки для линзы поверх сетки.
private nonisolated struct SelectedCellAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
