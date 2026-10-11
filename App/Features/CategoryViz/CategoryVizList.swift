import SwiftUI
import ExpenseCore

/// Список категорий под «Плитками», «Солнцем» и «Кольцом» (`04-stats`, `-drill`): строка 48 —
/// плашка 36, имя SF 17, доля SF 13 («6%, подкатегорий нет»), сумма, шеврон у раскрываемых.
/// Свёрнутые в «Ещё N» тоже здесь — всё остаётся касаемым. В раскрытом виде — строка категории
/// с шевроном вниз и строки подкатегорий: плашка 28 оттенком, «69% категории».
/// На AX-размерах сумма уходит под текст (как в `ExpenseRow`), иначе имя обрезается до «Ка…».
struct CategoryVizList: View {
    let data: CategoryVizData
    @Binding var expandedID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.moneyFormatter) private var money
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var expanded: CategoryVizGroup? { data.expandedGroup(expandedID) }
    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }
    private var textLineLimit: Int { isStacked ? 3 : 1 }

    var body: some View {
        let text = VizText(money: money)
        let motion = VizMotion(isExpanded: expanded != nil, reduceMotion: reduceMotion)
        VStack(spacing: 0) {
            ForEach(groups) { group in
                groupRow(group, text: text)
                    .transition(.opacity)
            }
            if let expanded {
                VStack(spacing: 0) {
                    ForEach(Array(expanded.parts.enumerated()), id: \.element.id) { index, part in
                        partRow(part, tone: expanded.tone, text: text)
                            .vizShade(index: index, visible: true)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(verbatim: L10n.format("stats.list.sub.group.a11y", VizText.name(expanded))))
                .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(Motion.vizShadesOut)))
            }
        }
        .animation(motion.shape, value: expandedID)
        .vizCrossfade(on: expanded?.id)
    }

    private var groups: [CategoryVizGroup] {
        expanded.map { [$0] } ?? data.groups
    }

    private func groupRow(_ group: CategoryVizGroup, text: VizText) -> some View {
        let isExpanded = expanded?.id == group.id
        return VizRowButton(
            action: group.isExpandable ? { expandedID = isExpanded ? nil : group.id } : nil,
            label: text.listLabel(group),
            hint: isExpanded ? Text("stats.center.back.a11y.hint")
                : (group.isExpandable ? Text("stats.list.group.a11y.hint") : nil)
        ) {
            HStack(alignment: isStacked ? .top : .center, spacing: Theme.Spacing.md) {
                CategoryPlaque(iconName: VizText.iconName(group), tone: group.tone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: VizText.name(group))
                        .typeStyle(.body)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(textLineLimit)
                    Text(verbatim: VizText.shareLine(group))
                        .typeStyle(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(textLineLimit)
                    if isStacked {
                        AmountText(text: text.amount(group.totalMinor), value: Double(group.totalMinor), size: .inline)
                    }
                }
                Spacer(minLength: Theme.Spacing.sm)
                if !isStacked {
                    AmountText(text: text.amount(group.totalMinor), value: Double(group.totalMinor), size: .inline)
                        .fixedSize()
                }
                if group.isExpandable {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: VizMetrics.chevron, weight: .semibold))
                        .foregroundStyle(Theme.graphic)
                        .frame(width: VizMetrics.chevron + Theme.Spacing.xs)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: VizMetrics.listRow)
            .contentShape(Rectangle())
        }
    }

    private func partRow(_ part: CategoryVizPart, tone: GouacheTone?, text: VizText) -> some View {
        HStack(alignment: isStacked ? .top : .center, spacing: Theme.Spacing.md + (Theme.Size.plaque - VizMetrics.listSubPlaque) / 2) {
            SubcategoryPlaque(part: part, tone: tone)
                .padding(.leading, (Theme.Size.plaque - VizMetrics.listSubPlaque) / 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: VizText.name(part))
                    .typeStyle(.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(textLineLimit)
                Text(verbatim: L10n.format("stats.list.sub.share", VizText.percent(part.share)))
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(textLineLimit)
                if isStacked {
                    AmountText(text: text.amount(part.totalMinor), value: Double(part.totalMinor), size: .inline)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            if !isStacked {
                AmountText(text: text.amount(part.totalMinor), value: Double(part.totalMinor), size: .inline)
                    .fixedSize()
            }
        }
        .frame(minHeight: VizMetrics.listRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text.label(part)))
    }
}

/// Плашка подкатегории 28: заливка оттенком с подписью по ступени, «без подкатегории» — штриховка.
struct SubcategoryPlaque: View {
    let part: CategoryVizPart
    let tone: GouacheTone?

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VizMetrics.listSubPlaqueRadius * scale, style: .continuous)
        VizPartFill(part: part, tone: tone)
            .clipShape(shape)
            .overlay {
                if !part.isUnassigned {
                    CategoryIconImage(name: part.iconName ?? CategoryIconAsset.fallbackName)
                        .frame(width: VizMetrics.listSubPlaqueIcon * scale, height: VizMetrics.listSubPlaqueIcon * scale)
                        .foregroundStyle(VizPaint.label(part, tone: tone))
                }
            }
            .frame(width: VizMetrics.listSubPlaque * scale, height: VizMetrics.listSubPlaque * scale)
            .accessibilityHidden(true)
    }
}
