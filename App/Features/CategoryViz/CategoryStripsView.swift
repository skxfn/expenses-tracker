import SwiftUI
import ExpenseCore

/// «Полосы»: полосы сами служат списком категорий, отдельного списка нет (DESIGN.md → «Полосы»,
/// `04-stats-strips`, `-drill`). Строка 56: плашка 36, имя 15/600 и доля 13/500, сумма справа;
/// под именем «выкраска» 18 с дыркой, сегменты подкатегорий 14 с зазором 2, «без подкатегории» — штриховка.
/// Раскрытие: строки подкатегорий, плашка категории — основной тон с иконкой paper-surface.
/// «Ещё N» раскрывается на месте: свёрнутые категории остаются касаемыми.
struct CategoryStripsView: View {
    let data: CategoryVizData
    @Binding var expandedID: UUID?
    /// Период для VoiceOver: «октябрь».
    var periodName: String = ""

    @State private var showsFolded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.moneyFormatter) private var money

    private var expanded: CategoryVizGroup? { data.expandedGroup(expandedID) }

    var body: some View {
        let rows = rows
        let scale = Double(rows.map(\.totalMinor).max() ?? 0)
        let motion = VizMotion(isExpanded: expanded != nil, reduceMotion: reduceMotion)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowView(row, scale: scale)
                    .modifier(StripRowAppearance(row: row, partIndex: partIndex(of: row, at: index)))
            }
        }
        .animation(motion.shape, value: expandedID)
        .animation(Motion.animation(Motion.vizExpand, reduceMotion: reduceMotion), value: showsFolded)
        .vizCrossfade(on: expanded?.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: L10n.format("stats.strips.a11y", periodName)))
    }

    // MARK: Строки

    private var rows: [StripRow] {
        if let expanded {
            return [.group(expanded, isExpanded: true)] + expanded.parts.map { .part($0, of: expanded) }
        }
        return data.itemsBySum.flatMap { item -> [StripRow] in
            switch item {
            case .group(let group):
                return [.group(group, isExpanded: false)]
            case .more(let more):
                return [.more(more)] + (showsFolded ? more.groups.map { .group($0, isExpanded: false) } : [])
            }
        }
    }

    private func partIndex(of row: StripRow, at index: Int) -> Int? {
        if case .part = row { return index - 1 }
        return nil
    }

    @ViewBuilder
    private func rowView(_ row: StripRow, scale: Double) -> some View {
        let text = VizText(money: money)
        switch row {
        case .group(let group, let isExpanded):
            groupRow(group, isExpanded: isExpanded, scale: scale, text: text)
        case .more(let more):
            moreRow(more, scale: scale, text: text)
        case .part(let part, let group):
            StripRowLayout(
                leading: {
                    CategoryIconImage(name: part.iconName ?? VizText.iconName(group))
                        .frame(width: Theme.Size.plaqueIcon, height: Theme.Size.plaqueIcon)
                        .foregroundStyle(CategoryPaint.onArea(group.tone))
                        .frame(width: Theme.Size.plaque, height: Theme.Size.plaque)
                },
                title: VizText.name(part),
                titleWeight: .medium,
                percent: VizText.percent(part.share),
                amount: text.amount(part.totalMinor),
                amountValue: part.totalMinor,
                card: StripCard(
                    segments: [StripSegment(part: part, tone: group.tone)],
                    fraction: scale > 0 ? Double(part.totalMinor) / scale : 0
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text.label(part)))
        }
    }

    private func groupRow(_ group: CategoryVizGroup, isExpanded: Bool, scale: Double, text: VizText) -> some View {
        let segments: [StripSegment] = group.isUncategorized
            ? [StripSegment(value: group.totalMinor, paint: .color(CategoryPaint.main(nil)))]
            : group.parts.map { part in
                isExpanded
                    ? StripSegment(value: part.totalMinor, paint: .color(CategoryPaint.area(group.tone)))
                    : StripSegment(part: part, tone: group.tone)
            }
        let row = StripRowLayout(
            leading: {
                CategoryPlaque(iconName: VizText.iconName(group), tone: group.tone, fill: isExpanded ? .main : .area)
            },
            title: VizText.name(group),
            titleWeight: .semibold,
            percent: VizText.percent(group.share),
            amount: text.amount(group.totalMinor),
            amountValue: group.totalMinor,
            card: StripCard(segments: segments, fraction: scale > 0 ? Double(group.totalMinor) / scale : 0)
        )
        return VizRowButton(
            action: group.isExpandable ? { expandedID = isExpanded ? nil : group.id } : nil,
            label: isExpanded ? text.centerLabel(group) : text.listLabel(group),
            hint: hint(for: group, isExpanded: isExpanded)
        ) {
            row
        }
    }

    private func hint(for group: CategoryVizGroup, isExpanded: Bool) -> Text? {
        if isExpanded { return Text("stats.center.back.a11y.hint") }
        return group.isExpandable ? Text("stats.list.group.a11y.hint") : nil
    }

    private func moreRow(_ more: CategoryVizMore, scale: Double, text: VizText) -> some View {
        let segments = more.groups.map { StripSegment(value: $0.totalMinor, paint: .color(VizPaint.fill($0))) }
        return VizRowButton(action: { showsFolded.toggle() }, label: text.statsMoreLabel(more), hint: nil) {
            StripRowLayout(
                leading: {
                    RoundedRectangle(cornerRadius: Theme.Radius.plaque, style: .continuous)
                        .fill(VizPaint.moreFill)
                        .strokeBorder(VizPaint.moreOutline, lineWidth: Theme.Size.hairline)
                        .frame(width: Theme.Size.plaque, height: Theme.Size.plaque)
                        .overlay {
                            VizMiniSwatches(more: more, limit: VizMiniSwatches.count(
                                fitting: Theme.Size.plaque - 2 * VizMetrics.miniSwatchGap
                            ))
                        }
                },
                title: VizText.moreTitle(more),
                titleWeight: .semibold,
                percent: VizText.percent(more.share),
                amount: text.amount(more.totalMinor),
                amountValue: more.totalMinor,
                card: StripCard(segments: segments, fraction: scale > 0 ? Double(more.totalMinor) / scale : 0)
            )
        }
        .accessibilityAddTraits(showsFolded ? .isSelected : [])
    }
}

// MARK: - Строки

private enum StripRow: Identifiable {
    case group(CategoryVizGroup, isExpanded: Bool)
    case more(CategoryVizMore)
    case part(CategoryVizPart, of: CategoryVizGroup)

    var id: String {
        switch self {
        case .group(let group, _): "group-\(group.id?.uuidString ?? "none")"
        case .more: "more"
        case .part(let part, _): "part-\(part.id?.uuidString ?? "none")"
        }
    }

    var totalMinor: Int64 {
        switch self {
        case .group(let group, _): group.totalMinor
        case .more(let more): more.totalMinor
        case .part(let part, _): part.totalMinor
        }
    }
}

/// Появление строк: подкатегории проявляются со стаггером, остальные — opacity вместе с формой.
private struct StripRowAppearance: ViewModifier {
    let row: StripRow
    let partIndex: Int?

    func body(content: Content) -> some View {
        if let partIndex {
            content
                .vizShade(index: partIndex, visible: true)
                .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(Motion.vizShadesOut)))
        } else {
            content.transition(.opacity)
        }
    }
}

/// Строка 56: колонка 36 слева, справа имя с долей и сумма, под ними «выкраска».
private struct StripRowLayout<Leading: View>: View {
    @ViewBuilder let leading: () -> Leading
    let title: String
    let titleWeight: Font.Weight
    let percent: String
    let amount: String
    let amountValue: Int64
    let card: StripCard

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // На AX-размерах имя, доля и сумма — друг под другом (как в списке под диаграммой), иначе имя режется.
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let labels = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        HStack(alignment: .top, spacing: VizMetrics.stripLabelInset - Theme.Size.plaque) {
            leading()
                .padding(.top, VizMetrics.stripPlaqueTop)
            VStack(alignment: .leading, spacing: VizMetrics.stripCardSpacing) {
                labels {
                    Text(verbatim: title)
                        .typeStyle(.callout)
                        .fontWeight(titleWeight)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(isStacked ? 3 : 1)
                    Text(verbatim: percent)
                        .typeStyle(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    if !isStacked {
                        Spacer(minLength: Theme.Spacing.sm)
                    }
                    AmountText(text: amount, value: Double(amountValue), size: .inline)
                        .fixedSize()
                }
                card
            }
            .padding(.top, VizMetrics.stripNameTop)
        }
        .frame(minHeight: Theme.Size.stripRow, alignment: .top)
        .contentShape(Rectangle())
    }
}

// MARK: - «Выкраска»

/// Сегмент «выкраски»: значение и заливка.
struct StripSegment {
    enum Paint {
        case color(Color)
        case hatch(GouacheTone)
    }

    let value: Int64
    let paint: Paint

    init(value: Int64, paint: Paint) {
        self.value = value
        self.paint = paint
    }

    /// Подкатегория — ступень оттенка, «без подкатегории» — штриховка.
    init(part: CategoryVizPart, tone: GouacheTone?) {
        value = part.totalMinor
        if part.isUnassigned, let tone {
            paint = .hatch(tone)
        } else {
            paint = .color(VizPaint.fill(part, tone: tone))
        }
    }
}

/// «Карточка-выкраска» 18: бумага с дыркой слева и сегментами 14 с зазором 2; длина — доля от наибольшей
/// строки (`fraction`).
struct StripCard: View {
    let segments: [StripSegment]
    let fraction: Double

    @Environment(\.colorScheme) private var colorScheme

    private static let chrome = VizMetrics.stripCardLeading + VizMetrics.stripCardPadding

    var body: some View {
        GeometryReader { proxy in
            let width = Self.chrome + (proxy.size.width - Self.chrome) * CGFloat(min(max(fraction, 0), 1))
            card(width: width)
        }
        .frame(height: VizMetrics.stripCardHeight)
        .accessibilityHidden(true)
    }

    private func card(width: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: VizMetrics.stripCardLeadingRadius,
            bottomLeadingRadius: VizMetrics.stripCardLeadingRadius,
            bottomTrailingRadius: VizMetrics.stripCardTrailingRadius,
            topTrailingRadius: VizMetrics.stripCardTrailingRadius,
            style: .continuous
        )
        let widths = chipWidths(in: width - Self.chrome)
        return ZStack(alignment: .leading) {
            shape
                .fill(Theme.surface)
                .paperShadow(Tokens.Shadow.swatchRest)
            shape.strokeBorder(Theme.separator, lineWidth: Theme.Size.hairline)
            Circle()
                .fill(holeColor)
                .frame(width: VizMetrics.stripHole, height: VizMetrics.stripHole)
                .padding(.leading, VizMetrics.stripHoleInset)
            HStack(spacing: Theme.Spacing.segmentGap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    chip(segment)
                        .frame(width: widths[index], height: VizMetrics.stripChipHeight)
                }
            }
            .padding(.leading, VizMetrics.stripCardLeading)
        }
        .frame(width: width, height: VizMetrics.stripCardHeight)
    }

    /// Дырка «выкраски»: графит 16 % на бумаге, в тёмной — почти чёрная (макет `dark/04-stats-strips`).
    private var holeColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.55) : Theme.graphite.opacity(0.16)
    }

    @ViewBuilder
    private func chip(_ segment: StripSegment) -> some View {
        let shape = RoundedRectangle(cornerRadius: VizMetrics.stripChipRadius, style: .continuous)
        switch segment.paint {
        case .color(let color):
            shape.fill(color)
        case .hatch(let tone):
            HatchFill(tone: tone).clipShape(shape)
        }
    }

    private func chipWidths(in available: CGFloat) -> [CGFloat] {
        let total = segments.reduce(0) { $0 + max($1.value, 0) }
        let gaps = Theme.Spacing.segmentGap * CGFloat(max(segments.count - 1, 0))
        let room = max(available - gaps, 0)
        guard total > 0 else { return segments.map { _ in 0 } }
        return segments.map { max(room * CGFloat(max($0.value, 0)) / CGFloat(total), VizMetrics.stripChipMinWidth) }
    }
}

// MARK: - Кнопка строки

/// Кнопка строки или диска с подписью VoiceOver; без действия — просто элемент с подписью.
struct VizRowButton<Label: View>: View {
    let action: (() -> Void)?
    let label: String
    let hint: Text?
    var pressScale: CGFloat = Motion.PressScale.row
    @ViewBuilder let content: () -> Label

    var body: some View {
        if let action {
            Button(action: action) { content() }
                .buttonStyle(.pressable(pressScale))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityHint(hint ?? Text(verbatim: ""))
                .accessibilityAddTraits(.isButton)
        } else {
            content()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
        }
    }
}
