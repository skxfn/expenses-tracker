import SwiftUI
import ExpenseCore

/// «2026 по дням» (`04-stats`): строка на месяц (`stats.year.months`), клетка на день по шкале heat
/// (одна с календарём, §8 п. 11), будущие дни — пустой контур, сегодня — обводка графитом. Клетки мельче 44,
/// поэтому карта — один элемент VoiceOver (`stats.year.a11y`, INTEGRATION §6); под ней шкала календаря.
/// Касание клетки выбирает день (обводка графитом с полем) и показывает под картой стеклянную подсказку
/// «Пт, 9 окт  57,20 ⃅» с шевроном — траты дня (`onShowDay`); повторное касание снимает выбор.
/// VoiceOver: смахивание вверх / вниз — следующий / предыдущий день с тратами, двойное касание — его траты.
struct StatsYearHeatmap: View {
    let state: StatsYearState
    let now: Date
    let texts: StatsTexts
    let legend: CalendarStrings
    /// Траты дня — списком; `nil` — без действия.
    var onShowDay: ((StatsTimeBucket) -> Void)?

    /// Шаг строки: клетка 9 + зазор 3 (макет: 24 px на 2x).
    @ScaledMetric(relativeTo: .caption2) private var rowHeight: CGFloat = 12
    @State private var cellsWidth: CGFloat = 0
    /// Выбранный день (начало дня).
    @State private var pin = StatsPin<Date>()
    @Environment(\.moneyFormatter) private var money
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                monthLabels
                cells
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: texts.yearAccessibility(state)))
            .accessibilityValue(Text(verbatim: selected.map { texts.bucketAccessibility($0, step: .day) } ?? ""))
            .accessibilityHint(canShow(selected) ? Text("stats.slice.a11y.hint") : Text(verbatim: ""))
            .accessibilityAdjustableAction(adjust)
            .accessibilityAction {
                if let day = selected, canShow(day) { onShowDay?(day) }
            }
            if let day = selected {
                tip(day)
                    .transition(.opacity)
            }
            HeatLegend(
                title: legend.legendTitle,
                items: legend.legendItems(state.scale),
                accessibilityText: legend.legendAccessibility(state.scale)
            )
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .animation(Motion.animation(Motion.chartTooltip, reduceMotion: reduceMotion), value: pin)
        .sensoryFeedback(Haptic.selection, trigger: pin)
        .onChange(of: state) { pin.reset() }
    }

    private var monthLabels: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(1...state.months.count, id: \.self) { month in
                Text(verbatim: L10n.format("stats.year.months.\(month)"))
                    .typeStyle(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: rowHeight)
            }
        }
    }

    private var cells: some View {
        Canvas { context, size in
            let width = cellWidth(in: size.width)
            let height = rowHeight - StatsLayout.yearRowGap
            for (row, days) in state.months.enumerated() {
                for (column, day) in days.enumerated() {
                    let rect = CGRect(
                        x: CGFloat(column) * (width + StatsLayout.yearCellGap),
                        y: CGFloat(row) * rowHeight + StatsLayout.yearRowGap / 2,
                        width: width,
                        height: height
                    )
                    draw(day, in: rect, context: &context)
                }
            }
        }
        .frame(height: rowHeight * CGFloat(state.months.count))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cellsWidth = $0 }
        .contentShape(Rectangle())
        .onTapGesture { location in
            if let day = day(at: location) { pin.toggle(day.id) }
        }
    }

    private var columns: Int { max(state.months.map(\.count).max() ?? 31, 1) }

    private func cellWidth(in width: CGFloat) -> CGFloat {
        (width - CGFloat(columns - 1) * StatsLayout.yearCellGap) / CGFloat(columns)
    }

    private func draw(_ day: StatsTimeBucket, in rect: CGRect, context: inout GraphicsContext) {
        let radius = StatsLayout.yearCellRadius
        let path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        if day.interval.start > now {
            let outline = Path(roundedRect: rect.insetBy(dx: Theme.Size.hairline / 2, dy: Theme.Size.hairline / 2), cornerRadius: radius)
            context.stroke(outline, with: .color(Theme.separator), lineWidth: Theme.Size.hairline)
            return
        }
        context.fill(path, with: .color(Theme.heat(state.scale.level(forMinor: day.totalMinor))))
        context.stroke(path, with: .color(Theme.hairlineOutline), lineWidth: Theme.Size.hairline)
        if day.interval.start <= now, now < day.interval.end {
            let line = StatsLayout.yearTodayLine
            let ring = Path(roundedRect: rect.insetBy(dx: -line / 2, dy: -line / 2), cornerRadius: radius + line / 2)
            context.stroke(ring, with: .color(Theme.ink), lineWidth: line)
        }
        if day.id == pin.value {
            // Выбранный день — обводка шире «сегодня» и с полем: видна и у сегодняшней клетки.
            let line = StatsLayout.selectionLine
            let outset = StatsLayout.yearTodayLine + line / 2
            let ring = Path(roundedRect: rect.insetBy(dx: -outset, dy: -outset), cornerRadius: radius + outset)
            context.stroke(ring, with: .color(Theme.ink), lineWidth: line)
        }
    }

    // MARK: Выбор дня

    private var days: [StatsTimeBucket] { state.months.flatMap { $0 } }

    private var selected: StatsTimeBucket? {
        pin.value.flatMap { value in days.first { $0.id == value } }
    }

    private func canShow(_ day: StatsTimeBucket?) -> Bool {
        onShowDay != nil && (day?.count ?? 0) > 0
    }

    /// Клетка под касанием; будущие дни не выбираются.
    private func day(at location: CGPoint) -> StatsTimeBucket? {
        let width = cellWidth(in: cellsWidth)
        guard width > 0, rowHeight > 0 else { return nil }
        let row = Int(location.y / rowHeight)
        let column = Int(location.x / (width + StatsLayout.yearCellGap))
        guard state.months.indices.contains(row), state.months[row].indices.contains(column) else { return nil }
        let day = state.months[row][column]
        return day.interval.start > now ? nil : day
    }

    /// VoiceOver: следующий / предыдущий день с тратами.
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let spending = days.filter { $0.count > 0 }
        let current = pin.value
        let next: StatsTimeBucket? = switch direction {
        case .increment: spending.first { day in current.map { day.id > $0 } ?? true }
        case .decrement: spending.last { day in current.map { day.id < $0 } ?? true }
        @unknown default: nil
        }
        if let next { pin.select(next.id) }
    }

    /// «Пт, 9 окт  57,20 ⃅ ›» — под картой, слева.
    private func tip(_ day: StatsTimeBucket) -> some View {
        let action: (() -> Void)? = if let onShowDay, day.count > 0 { { onShowDay(day) } } else { nil }
        return StatsSliceTip(action: action) {
            StatsTipLine(title: texts.bucketTitle(day, step: .day), value: money.string(fromMinor: day.totalMinor))
        }
        .vizDynamicTypeLimit()
    }
}
