import SwiftUI
import ExpenseCore

// MARK: - Обёртки для экранов

/// «Кольцо» на главной (`02-home-ring`): R 110 / r 82, порядок по оттенку, зазор 2, скругление концов,
/// кружки-плашки r 18 над сегментами, зерно и блик. В центре — итог Unbounded 28 и фраза SF 13 от экрана.
/// Без раскрытия: тап по сегменту или кружку — колбэк (экран открывает статистику категории).
struct HomeCategoryRing<Phrase: View>: View {
    let data: CategoryVizData
    /// Период для VoiceOver: «октябрь» → «Траты за октябрь по категориям».
    var periodName: String = ""
    var onSelect: (CategoryVizItemID) -> Void
    /// Фраза-сравнение под итогом («на 38 Br меньше, чем в прошлом месяце»): стиль SF 13 задаёт кольцо,
    /// выделение — `AttributedString` экрана.
    @ViewBuilder let phrase: () -> Phrase

    @Environment(\.moneyFormatter) private var money

    var body: some View {
        CircleVizBody(
            data: data,
            ring: .home,
            outerRing: nil,
            mode: .home,
            expandedID: nil,
            fieldHeight: RingMetrics.home.fieldHeight,
            showsGrain: true,
            onSelect: onSelect
        ) {
            VStack(spacing: Theme.Spacing.xs) {
                AmountText(
                    text: money.string(fromMinor: data.totalMinor, style: .plain),
                    value: Double(data.totalMinor),
                    size: .ringTotal,
                    currency: money.currencySymbol,
                    accessibilityText: VizText(money: money).spoken(data.totalMinor)
                )
                .minimumScaleFactor(VizMetrics.centerAmountMinScale)
                .frame(maxWidth: RingMetrics.home.centerWidth)
                phrase()
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: RingMetrics.home.centerWidth)
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityLabel(Text(verbatim: L10n.format("home.map.a11y", periodName)))
    }
}

/// «Кольцо» в статистике (`04-stats-ring`, `-drill`): поле 358 × 320, R ≈ 114 / r ≈ 83.
/// В центре «412,30 · Br · 18 трат»; в раскрытом виде — «Категория, сумма», тап по центру — назад.
struct CategoryRingView: View {
    let data: CategoryVizData
    @Binding var expandedID: UUID?
    var periodName: String = ""

    var body: some View {
        CircleVizBody(
            data: data,
            ring: .stats,
            outerRing: nil,
            mode: .stats,
            expandedID: data.expandedGroup(expandedID)?.id,
            fieldHeight: VizMetrics.circleFieldHeight,
            showsGrain: false,
            onSelect: select
        ) {
            StatsCircleCenter(data: data, expanded: data.expandedGroup(expandedID), ring: .stats) { expandedID = nil }
        }
        .accessibilityLabel(Text(verbatim: L10n.format("stats.ring.a11y", VizText.sharesList(data))))
    }

    private func select(_ id: CategoryVizItemID) {
        if case .category(let groupID) = id { expandedID = groupID }
    }
}

/// «Солнце» (`04-stats-sun`, `-drill`): поле 358 × 320, внутреннее кольцо категорий ≈ 71–100,
/// внешнее подкатегорий ≈ 103–109 оттенками, «без подкатегории» — штриховка; подписи — диски 32–36.
/// Раскрытие: категория занимает внутреннее кольцо, оттенки подкатегорий — на нём, внешнее гаснет.
struct CategorySunView: View {
    let data: CategoryVizData
    @Binding var expandedID: UUID?
    var periodName: String = ""

    var body: some View {
        CircleVizBody(
            data: data,
            ring: .sunInner,
            outerRing: .sunOuter,
            mode: .stats,
            expandedID: data.expandedGroup(expandedID)?.id,
            fieldHeight: VizMetrics.circleFieldHeight,
            showsGrain: false,
            onSelect: select
        ) {
            StatsCircleCenter(data: data, expanded: data.expandedGroup(expandedID), ring: .sunInner) { expandedID = nil }
        }
        .accessibilityLabel(Text(verbatim: L10n.format("stats.sun.a11y", VizText.sharesList(data))))
    }

    private func select(_ id: CategoryVizItemID) {
        if case .category(let groupID) = id { expandedID = groupID }
    }
}

// MARK: - Общее тело кругов

/// Сегменты по оттенку, диски-подписи над ними, центр. Раскрытие: сегмент категории разрастается
/// в полный круг (`viz-expand`), остальные гаснут, оттенки подкатегорий проявляются со стаггером.
private struct CircleVizBody<Center: View>: View {
    let data: CategoryVizData
    let ring: RingMetrics
    /// Внешнее кольцо подкатегорий («Солнце»).
    let outerRing: RingMetrics?
    let mode: CategoryVizMode
    /// Раскрытая категория (уже проверенная: есть в данных и раскрывается).
    let expandedID: UUID?
    let fieldHeight: CGFloat
    let showsGrain: Bool
    let onSelect: (CategoryVizItemID) -> Void
    @ViewBuilder let center: () -> Center

    @State private var lastExpandedID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.moneyFormatter) private var money

    private var expanded: CategoryVizGroup? { data.expandedGroup(expandedID) }
    private var shown: CategoryVizGroup? { expanded ?? data.expandedGroup(lastExpandedID) }
    private var motion: VizMotion { VizMotion(isExpanded: expanded != nil, reduceMotion: reduceMotion) }
    private var items: [CategoryVizItem] { data.itemsByHue }
    private var arcs: [RingArc] { RingLayout.arcs(items.map { Double($0.totalMinor) }, gap: ring.gapAngle()) }

    var body: some View {
        let arcs = arcs
        ZStack {
            segments(arcs)
                .overlay {
                    if showsGrain {
                        VizGrainOverlay().mask { segments(arcs) }
                    }
                }
            if let outerRing {
                outerSegments(arcs, metrics: outerRing)
            }
            if let shown {
                parts(of: shown)
            }
            discs(arcs)
            center()
                .animation(motion.shape, value: expandedID)
        }
        .frame(maxWidth: .infinity, minHeight: fieldHeight, maxHeight: fieldHeight)
        .onChange(of: expandedID, initial: true) { _, id in
            if let id { lastExpandedID = id }
        }
        .vizCrossfade(on: expandedID)
        .vizDynamicTypeLimit()
        .accessibilityElement(children: .contain)
    }

    // MARK: Сегменты категорий

    private func segments(_ arcs: [RingArc]) -> some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                segment(item, arc: arcs[index])
            }
        }
    }

    private func isExpanded(_ item: CategoryVizItem) -> Bool {
        expanded?.id.map(CategoryVizItemID.category) == item.id
    }

    private func segment(_ item: CategoryVizItem, arc: RingArc) -> some View {
        let isExpanded = isExpanded(item)
        let hidden = expanded != nil && !isExpanded
        let shownArc = isExpanded ? RingArc(start: RingLayout.top, end: RingLayout.top + 2 * .pi) : arc
        let sector = AnnularSector(shownArc, inner: ring.inner, outer: ring.outer, corner: ring.corner)
        let lastShade = max((expanded?.parts.count ?? 1) - 1, 0)
        return segmentFill(item, arc: arc)
            .clipShape(sector)
            .contentShape(sector)
            .onTapGesture { tap(item) }
            .animation(motion.shape, value: expandedID)
            .opacity(isExpanded ? 0 : 1)
            .animation(isExpanded ? motion.base(lastShadeIndex: lastShade) : nil, value: isExpanded)
            .opacity(hidden ? 0 : 1)
            .animation(motion.others, value: hidden)
            .allowsHitTesting(expanded == nil)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func segmentFill(_ item: CategoryVizItem, arc: RingArc) -> some View {
        switch item {
        case .group(let group):
            Rectangle().fill(VizPaint.fill(group))
        case .more(let more):
            // «Ещё N»: мини-образцы цветов внутри сегмента.
            let parts = RingLayout.subdivide(arc, values: more.groups.map { Double($0.totalMinor) }, gap: 0)
            ZStack {
                ForEach(Array(more.groups.enumerated()), id: \.offset) { index, group in
                    AnnularSector(parts[index], inner: ring.inner, outer: ring.outer)
                        .fill(VizPaint.fill(group))
                }
            }
        }
    }

    // MARK: Внешнее кольцо подкатегорий («Солнце»)

    private func outerSegments(_ arcs: [RingArc], metrics: RingMetrics) -> some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if case .group(let group) = item, !group.isUncategorized {
                    let partArcs = RingLayout.subdivide(
                        arcs[index], values: group.parts.map { Double($0.totalMinor) }, gap: metrics.gapAngle()
                    )
                    ForEach(Array(group.parts.enumerated()), id: \.element.id) { partIndex, part in
                        let sector = AnnularSector(partArcs[partIndex], inner: metrics.inner, outer: metrics.outer,
                                                   corner: metrics.corner)
                        VizPartFill(part: part, tone: group.tone)
                            .clipShape(sector)
                            .contentShape(sector)
                            .onTapGesture { tap(item) }
                    }
                }
            }
        }
        .opacity(expanded == nil ? 1 : 0)
        .animation(motion.others, value: expanded == nil)
        .allowsHitTesting(expanded == nil)
        .accessibilityHidden(true)
    }

    // MARK: Оттенки раскрытой категории

    private func parts(of group: CategoryVizGroup) -> some View {
        let partArcs = RingLayout.arcs(group.parts.map { Double($0.totalMinor) }, gap: ring.gapAngle())
        let separation = ring.discSeparation
        let discAngles = RadialLabelLayout.spread(partArcs.map(\.mid), minSeparation: separation)
        let isVisible = expanded?.id == group.id
        let text = VizText(money: money)
        return ZStack {
            ForEach(Array(group.parts.enumerated()), id: \.element.id) { index, part in
                VizPartFill(part: part, tone: group.tone)
                    .clipShape(AnnularSector(partArcs[index], inner: ring.inner, outer: ring.outer, corner: ring.corner))
                    .vizShade(index: index, visible: isVisible)
                    .accessibilityHidden(true)
            }
            // Диски — по сумме: VoiceOver идёт по порядку элементов; место на круге — по оттенку (`index`).
            ForEach(Array(partsBySum(group).enumerated()), id: \.element.part.id) { rank, entry in
                VizDisc(content: partDiscContent(entry.part, of: group), radius: ring.discRadius)
                    .offset(discOffset(discAngles[entry.index]))
                    .vizShade(index: entry.index, visible: isVisible)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: text.label(entry.part)))
                    .accessibilitySortPriority(VizText.sortPriority(rank, count: group.parts.count))
                    .accessibilityHidden(!isVisible)
            }
        }
        .allowsHitTesting(false)
    }

    private func partDiscContent(_ part: CategoryVizPart, of group: CategoryVizGroup) -> VizDisc.Content {
        if part.isUnassigned, let tone = group.tone { return .hatch(tone) }
        return .icon(part.iconName ?? VizText.iconName(group), group.tone)
    }

    /// Части по убыванию суммы с их местом в порядке оттенков.
    private func partsBySum(_ group: CategoryVizGroup) -> [(index: Int, part: CategoryVizPart)] {
        group.parts.enumerated()
            .map { (index: $0.offset, part: $0.element) }
            .sorted { $0.part.totalMinor > $1.part.totalMinor }
    }

    // MARK: Диски-подписи

    private func discs(_ arcs: [RingArc]) -> some View {
        let angles = RadialLabelLayout.spread(arcs.map(\.mid), minSeparation: ring.discSeparation)
        let hueIndex = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        let text = VizText(money: money)
        return ZStack {
            // Диски — по сумме, как во фразе `stats.ring.a11y`: VoiceOver идёт по порядку элементов;
            // место на круге — по оттенку.
            ForEach(Array(data.itemsBySum.enumerated()), id: \.element.id) { rank, item in
                let index = hueIndex[item.id] ?? rank
                VizRowButton(
                    action: isTappable(item) ? { tap(item) } : nil,
                    label: label(item, text: text),
                    hint: hint(item),
                    pressScale: Motion.PressScale.circle
                ) {
                    VizDisc(content: discContent(item), radius: ring.discRadius)
                }
                .offset(discOffset(angles[index]))
                .accessibilitySortPriority(VizText.sortPriority(rank, count: items.count))
            }
        }
        .opacity(expanded == nil ? 1 : 0)
        .animation(motion.others, value: expanded == nil)
        .allowsHitTesting(expanded == nil)
        .accessibilityHidden(expanded != nil)
    }

    private func discContent(_ item: CategoryVizItem) -> VizDisc.Content {
        switch item {
        case .group(let group): .icon(VizText.iconName(group), group.tone)
        case .more(let more): .more(more)
        }
    }

    private func discOffset(_ angle: Double) -> CGSize {
        CGSize(width: ring.discOrbit * CGFloat(cos(angle)), height: ring.discOrbit * CGFloat(sin(angle)))
    }

    // MARK: Касания и озвучка

    private func isTappable(_ item: CategoryVizItem) -> Bool {
        switch (mode, item) {
        case (.home, _): true
        case (.stats, .group(let group)): group.isExpandable
        case (.stats, .more): false
        }
    }

    private func tap(_ item: CategoryVizItem) {
        guard expanded == nil, isTappable(item) else { return }
        onSelect(item.id)
    }

    private func label(_ item: CategoryVizItem, text: VizText) -> String {
        switch item {
        case .group(let group): text.label(group)
        case .more(let more): mode == .home ? text.homeMoreLabel(more) : text.statsMoreLabel(more)
        }
    }

    private func hint(_ item: CategoryVizItem) -> Text? {
        switch (mode, item) {
        case (.home, .more): Text("home.more.a11y.hint")
        case (.home, .group): Text("home.map.tile.a11y.hint")
        case (.stats, _): isTappable(item) ? Text("stats.map.tile.a11y.hint") : nil
        }
    }
}

// MARK: - Диск-подпись

/// Кружок-плашка над сегментом: tint + deep-иконка (в тёмной — darktint + tint), белый контур 1.
/// Цель касания — 44 (невидимая рамка вокруг диска).
struct VizDisc: View {
    enum Content {
        case icon(String, GouacheTone?)
        case more(CategoryVizMore)
        case hatch(GouacheTone)
    }

    let content: Content
    let radius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            switch content {
            case .icon(let name, let tone):
                Circle().fill(CategoryPaint.area(tone))
                CategoryIconImage(name: name)
                    .frame(width: radius, height: radius)
                    .foregroundStyle(CategoryPaint.onArea(tone))
            case .more(let more):
                Circle().fill(VizPaint.moreFill)
                VizMiniSwatches(more: more, limit: VizMiniSwatches.count(fitting: 2 * radius - 2 * VizMetrics.miniSwatchGap))
            case .hatch(let tone):
                HatchFill(tone: tone).clipShape(Circle())
            }
        }
        .frame(width: 2 * radius, height: 2 * radius)
        .overlay { Circle().strokeBorder(outline, lineWidth: 1) }
        .paperShadow(Tokens.Shadow.segmentActive)
        .frame(width: max(2 * radius, Theme.Size.iconButton), height: max(2 * radius, Theme.Size.iconButton))
        .contentShape(Circle())
    }

    /// Белый контур 1 (DESIGN.md → «Кольцо»); в тёмной — едва заметный светлый.
    private var outline: Color {
        Color.white.opacity(colorScheme == .dark ? 0.12 : 1)
    }
}

// MARK: - Центр в статистике

/// Центр «Кольца» и «Солнца» в статистике: «412,30» и «Br · 18 трат»; в раскрытом виде — иконка,
/// сумма и имя категории (deep / в тёмной tint), тап — назад ко всем категориям.
private struct StatsCircleCenter: View {
    let data: CategoryVizData
    let expanded: CategoryVizGroup?
    let ring: RingMetrics
    let onBack: () -> Void

    @Environment(\.moneyFormatter) private var money

    var body: some View {
        ZStack {
            if let expanded {
                Button(action: onBack) { groupCenter(expanded) }
                    .buttonStyle(.pressable(Motion.PressScale.circle))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: VizText(money: money).centerLabel(expanded)))
                    .accessibilityHint(Text("stats.center.back.a11y.hint"))
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
            } else {
                totalCenter
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: ring.centerWidth)
    }

    private var totalCenter: some View {
        VStack(spacing: 2) {
            AmountText(
                text: money.string(fromMinor: data.totalMinor, style: .plain),
                value: Double(data.totalMinor),
                size: .ringTotal
            )
            .minimumScaleFactor(VizMetrics.centerAmountMinScale)
            Text(verbatim: L10n.format("stats.center.meta", money.currencySymbol, data.count))
                .typeStyle(.footnote)
                .foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .ignore)
        // «480,15 рубля · 19 трат»: та же строка, вместо знака — сумма словами.
        .accessibilityLabel(Text(verbatim: L10n.format("stats.center.meta", VizText(money: money).spoken(data.totalMinor), data.count)))
    }

    private func groupCenter(_ group: CategoryVizGroup) -> some View {
        VStack(spacing: 2) {
            CategoryIconImage(name: VizText.iconName(group))
                .frame(width: VizMetrics.centerIcon, height: VizMetrics.centerIcon)
                .foregroundStyle(CategoryPaint.onArea(group.tone))
            AmountText(
                text: money.string(fromMinor: group.totalMinor, style: .plain),
                value: Double(group.totalMinor),
                size: .ringTotal
            )
            .minimumScaleFactor(VizMetrics.centerAmountMinScale)
            Text(verbatim: VizText.name(group))
                .typeStyle(.callout)
                .foregroundStyle(CategoryPaint.onArea(group.tone))
                .lineLimit(1)
        }
        .contentShape(Circle())
    }
}
