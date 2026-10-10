import SwiftUI
import ExpenseCore

/// «2026 по дням» (`04-stats`): строка на месяц (`stats.year.months`), клетка на день по шкале heat
/// (одна с календарём, §8 п. 11), будущие дни — пустой контур, сегодня — обводка графитом. Клетки мельче 44,
/// поэтому карта — один элемент VoiceOver (`stats.year.a11y`, INTEGRATION §6); под ней шкала календаря.
struct StatsYearHeatmap: View {
    let state: StatsYearState
    let now: Date
    let texts: StatsTexts
    let legend: CalendarStrings

    /// Шаг строки: клетка 9 + зазор 3 (макет: 24 px на 2x).
    @ScaledMetric(relativeTo: .caption2) private var rowHeight: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                monthLabels
                cells
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: texts.yearAccessibility(state)))
            HeatLegend(
                title: legend.legendTitle,
                items: legend.legendItems(state.scale),
                accessibilityText: legend.legendAccessibility(state.scale)
            )
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
            let columns = max(state.months.map(\.count).max() ?? 31, 1)
            let gap = StatsLayout.yearCellGap
            let width = (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            let height = rowHeight - StatsLayout.yearRowGap
            for (row, days) in state.months.enumerated() {
                for (column, day) in days.enumerated() {
                    let rect = CGRect(
                        x: CGFloat(column) * (width + gap),
                        y: CGFloat(row) * rowHeight + StatsLayout.yearRowGap / 2,
                        width: width,
                        height: height
                    )
                    draw(day, in: rect, context: &context)
                }
            }
        }
        .frame(height: rowHeight * CGFloat(state.months.count))
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
    }
}
