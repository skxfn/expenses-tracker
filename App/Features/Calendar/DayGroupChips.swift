import SwiftUI
import ExpenseCore

/// Доли категорий выбранного дня над его тратами: плашки «Кафе 78%» по сумме — tint категории, иконка deep,
/// текст графитом (DESIGN.md: большие площади — тинтом, подписи на цвете — графитом). Переносятся по строкам.
/// Нажатие оставляет в листе только траты этой категории, повторное — снимает фильтр; выбранная плашка обведена
/// графитом, как выбранный цвет в редакторе категории.
struct DayGroupChips: View {
    struct Item: Identifiable, Hashable {
        /// `.group(id)` или `.uncategorized`.
        let filter: StatsCategoryFilter
        let name: String
        let iconName: String
        let tone: GouacheTone?
        /// Доля в тратах дня (D7): «78%».
        let share: String
        /// `cal.day.group.a11y`.
        let accessibilityLabel: String

        var id: StatsCategoryFilter { filter }
    }

    let items: [Item]
    /// Выбранная категория; `.all` — фильтра нет.
    let selection: StatsCategoryFilter
    let onToggle: (StatsCategoryFilter) -> Void

    @ScaledMetric(relativeTo: .footnote) private var height = CalendarMetrics.groupChipHeight
    @ScaledMetric(relativeTo: .footnote) private var icon = CalendarMetrics.groupChipIcon

    var body: some View {
        // Место под обводку есть у каждой плашки — выбор не сдвигает соседей; зазор между плашками — эти поля.
        FlowLayout(spacing: 0, lineSpacing: 0) {
            ForEach(items) { item in
                chip(item)
            }
        }
        .padding(.horizontal, -Self.ringSpace)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ item: Item) -> some View {
        let isSelected = item.filter == selection
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
        return Button {
            onToggle(item.filter)
        } label: {
            HStack(spacing: Theme.Spacing.xs + 2) {
                CategoryIconImage(name: item.iconName)
                    .frame(width: icon, height: icon)
                    .foregroundStyle(CategoryPaint.onArea(item.tone))
                Text(verbatim: item.name)
                    .typeStyle(.footnoteStrong)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(verbatim: item.share)
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, CalendarMetrics.groupChipPadding)
            .frame(minHeight: height)
            .background(CategoryPaint.area(item.tone), in: shape)
            .padding(Self.ringSpace)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.swatch + Self.ringSpace, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: CalendarMetrics.groupChipRing)
                    .opacity(isSelected ? 1 : 0)
            }
            // Цель касания — не меньше 44 в высоту.
            .frame(minHeight: Theme.Size.chip)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(Motion.PressScale.tile))
        .accessibilityLabel(Text(verbatim: item.accessibilityLabel))
        .accessibilityHint(Text("cal.day.group.a11y.hint"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static let ringSpace = CalendarMetrics.groupChipRing + CalendarMetrics.groupChipRingGap
}
