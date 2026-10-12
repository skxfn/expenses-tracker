import SwiftUI
import ExpenseCore

/// Сетка месяца: дни недели с `calendar.firstWeekday` и 4–6 недель по 7 клеток с зазором 4.
/// Свайп влево / вправо листает месяц; смена месяца — растворение (без полёта: и при Reduce Motion то же).
/// Линза выбранного дня рисуется слоем поверх сетки по рамке клетки (`SelectedCellAnchorKey`): выступ линзы должен
/// лежать поверх соседей, а `zIndex` у клетки уводил её в конец порядка VoiceOver (после 31-го).
/// Выбор другого дня — линза переезжает к нему пружиной `morph`; при Reduce Motion — гаснет и проявляется.
struct CalendarGrid: View {
    let model: CalendarModel
    let strings: CalendarStrings
    let onSelect: (Date) -> Void
    let onAdd: (Date) -> Void
    let onSwipe: (_ forward: Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        Grid(horizontalSpacing: CalendarMetrics.gridGap, verticalSpacing: CalendarMetrics.gridGap) {
            ForEach(Array(model.month.weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        if let date {
                            dayView(date)
                        } else {
                            Color.clear.gridCellUnsizedAxes(.vertical)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayView(_ date: Date) -> some View {
        let day = model.day(date)
        let isSelected = date == model.selectedDay
        let isPeak = date == model.summary.peakDay
        let amount = strings.cellAmount(day.totalMinor)
        let cell = CalendarDayCell(day: day, number: strings.dayNumber(date), amount: amount, isSelected: isSelected)
        let label = Text(verbatim: strings.dayAccessibility(day, isSelected: isSelected, isPeak: isPeak))

        if day.isSelectable {
            let marksSelection = isSelected && !strings.accessibilityStatesSelection(day, isSelected: isSelected)
            Button {
                onSelect(date)
            } label: {
                cell
            }
            .buttonStyle(.pressable(Motion.PressScale.tile))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: Self.longPressDuration).onEnded { _ in onAdd(date) }
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
    /// Одна линза на сетку переезжает от дня к дню; при Reduce Motion у каждого дня своя — без перелёта.
    @ViewBuilder
    private func selectionLens(_ anchor: Anchor<CGRect>?) -> some View {
        if let anchor {
            let day = model.selected
            GeometryReader { proxy in
                let rect = proxy[anchor].insetBy(dx: -CalendarMetrics.lensOutset, dy: -CalendarMetrics.lensOutset)
                ZStack {
                    DayLens(
                        number: strings.dayNumber(day.date),
                        amount: strings.cellAmount(day.totalMinor),
                        level: day.level,
                        isToday: day.isToday
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .id(reduceMotion ? day.date : nil)
                    .transition(.opacity)
                }
                .animation(Motion.animation(Motion.morph, reduceMotion: reduceMotion), value: day.date)
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

/// Рамка выбранной клетки для линзы поверх сетки.
private nonisolated struct SelectedCellAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
