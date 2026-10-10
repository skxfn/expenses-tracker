import SwiftUI
import ExpenseCore

/// Сетка месяца: дни недели с `calendar.firstWeekday` и 4–6 недель по 7 клеток с зазором 4.
/// Свайп влево / вправо листает месяц; смена месяца — растворение (без полёта: и при Reduce Motion то же).
struct CalendarGrid: View {
    let model: CalendarModel
    let strings: CalendarStrings
    let onSelect: (Date) -> Void
    let onAdd: (Date) -> Void
    let onSwipe: (_ forward: Bool) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            weekdays
            ZStack {
                weeks
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
            .zIndex(day.isToday ? 1 : 0)
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

    /// Горизонтальный свайп: влево — следующий месяц, вправо — предыдущий.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: Theme.Spacing.xl).onEnded { value in
            let dx = value.translation.width
            guard abs(dx) > CalendarMetrics.swipeDistance, abs(dx) > abs(value.translation.height) * 1.5 else { return }
            onSwipe(dx < 0)
        }
    }

    private static let longPressDuration = 0.5

    /// Ключ `cal.weekdays.*` по номеру дня недели `Calendar` (1 — воскресенье).
    private static func weekdayKey(_ weekday: Int) -> String {
        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        return "cal.weekdays." + names[(weekday - 1) % names.count]
    }
}
