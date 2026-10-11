import SwiftUI
import ExpenseCore

/// Уровень плиток в раскрытой категории (переключатель «Категории / Подкатегории», `viz.level.*`).
enum CategoryTilesLevel: Hashable, CaseIterable {
    /// Карта всех категорий; раскрытая разделена на оттенки внутри своей плитки: зазор 1, внутренние углы 2.
    case categories
    /// Подкатегории раскрытой категории на всё поле (`04-stats-map-drill`).
    case subcategories
}

/// Где показываются визуализации: обзор на главной (без раскрытия, тап — колбэк) или статистика.
enum CategoryVizMode: Hashable {
    case home
    case stats
}

/// «Плитки»: squarified treemap по сумме (DESIGN.md → «Плитки», `01-home`, `04-stats`, `04-stats-map-drill`).
/// Плитка — основной тон, иконка в углу, сумма Unbounded 15 — только где помещается; в статистике ещё
/// доля и имя. Раскрытие: плитка категории разрастается на всё поле, оттенки подкатегорий проявляются
/// со стаггером, «без подкатегории» — штриховка.
struct CategoryTilesView: View {
    let data: CategoryVizData
    /// Раскрытая категория (только статистика). Не раскрываемая и отсутствующая в данных — обзор.
    @Binding var expandedID: UUID?
    var level: CategoryTilesLevel
    /// Период для VoiceOver: «октябрь» → «Плитки: траты за октябрь по категориям».
    var periodName: String
    private let mode: CategoryVizMode
    /// Тап по плитке на главной (любая часть). В статистике тап раскрывает категорию.
    private let onHomeSelect: (CategoryVizItemID) -> Void

    /// Статистика: подписи с долями и именами, раскрытие до подкатегорий.
    init(
        data: CategoryVizData,
        expandedID: Binding<UUID?>,
        level: CategoryTilesLevel = .subcategories,
        periodName: String = ""
    ) {
        self.data = data
        _expandedID = expandedID
        self.level = level
        self.periodName = periodName
        mode = .stats
        onHomeSelect = { _ in }
    }

    /// Главная: только суммы, без раскрытия; тап — колбэк.
    init(homeData data: CategoryVizData, periodName: String = "", onSelect: @escaping (CategoryVizItemID) -> Void) {
        self.data = data
        _expandedID = .constant(nil)
        level = .subcategories
        self.periodName = periodName
        mode = .home
        onHomeSelect = onSelect
    }

    @State private var width: CGFloat = 0
    @State private var lastExpandedID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.moneyFormatter) private var money

    private var height: CGFloat {
        mode == .home ? VizMetrics.homeTilesHeight : VizMetrics.statsTilesHeight
    }

    private var expanded: CategoryVizGroup? {
        mode == .stats ? data.expandedGroup(expandedID) : nil
    }

    /// Категория, чьи оттенки на поле: раскрытая или только что свёрнутая (оттенки гаснут).
    private var shown: CategoryVizGroup? {
        expanded ?? (mode == .stats ? data.expandedGroup(lastExpandedID) : nil)
    }

    private var motion: VizMotion {
        VizMotion(isExpanded: expanded != nil, reduceMotion: reduceMotion)
    }

    /// Уровень на деле: свёрнутая в «Ещё N» категория своей плитки не имеет — только на всё поле.
    private var effectiveLevel: CategoryTilesLevel {
        guard level == .categories, let shown,
              data.itemsBySum.contains(where: { $0.id == shown.id.map(CategoryVizItemID.category) })
        else { return .subcategories }
        return .categories
    }

    private var motionKey: TilesMotionKey { TilesMotionKey(expandedID: expanded?.id, level: effectiveLevel) }

    var body: some View {
        let field = CGRect(x: 0, y: 0, width: width, height: height)
        let items = data.itemsBySum
        let rects = TileLayout.rects(items.map { Double($0.totalMinor) }, in: field, gap: Theme.Spacing.categoryGap,
                                     minSide: VizMetrics.tileMinSide)
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                itemTile(item, overview: rects[index], field: field)
            }
            if let shown {
                let index = items.firstIndex { $0.id == shown.id.map(CategoryVizItemID.category) }
                parts(of: shown, overview: index.map { rects[$0] } ?? field, field: field)
                    .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: expanded?.id, initial: true) { _, id in
            if let id { lastExpandedID = id }
        }
        .vizCrossfade(on: motionKey)
        .vizDynamicTypeLimit()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: containerLabel))
    }

    private var containerLabel: String {
        L10n.format(mode == .home ? "home.map.a11y" : "stats.map.a11y", periodName)
    }

    // MARK: Плитки категорий

    private func itemTile(_ item: CategoryVizItem, overview: CGRect, field: CGRect) -> some View {
        let isExpanded = expanded?.id.map(CategoryVizItemID.category) == item.id
        let level = effectiveLevel
        let rect = isExpanded && level == .subcategories ? field : overview
        let hidesOthers = expanded != nil && !isExpanded && level == .subcategories
        let lastShade = max((expanded?.parts.count ?? 1) - 1, 0)
        let text = VizText(money: money)
        return ItemTile(item: item, mode: mode, size: rect.size, text: text)
            .modifier(TileInteraction(item: item, mode: mode, isActive: expanded == nil, text: text, onSelect: select))
            .opacity(isExpanded ? 0 : 1)
            .animation(isExpanded ? motion.base(lastShadeIndex: lastShade) : nil, value: isExpanded)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .animation(motion.shape, value: motionKey)
            .opacity(hidesOthers ? 0 : 1)
            .animation(motion.others, value: hidesOthers)
            .zIndex(isExpanded ? 1 : 0)
    }

    private func select(_ id: CategoryVizItemID) {
        switch mode {
        case .home: onHomeSelect(id)
        case .stats: if case .category(let groupID) = id { expandedID = groupID }
        }
    }

    // MARK: Оттенки раскрытой категории

    private func parts(of group: CategoryVizGroup, overview: CGRect, field: CGRect) -> some View {
        let level = effectiveLevel
        let container = level == .subcategories ? field : overview
        let gap = level == .subcategories ? Theme.Spacing.categoryGap : Theme.Spacing.subcategoryGap
        let rects = TileLayout.rects(group.parts.map { Double($0.totalMinor) }, in: container, gap: gap)
        let isVisible = expanded?.id == group.id
        let text = VizText(money: money)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(group.parts.enumerated()), id: \.element.id) { index, part in
                let rect = rects[index]
                let corners = level == .subcategories
                    ? TileCorners.tile
                    : TileCorners(of: rect, in: container, outer: Theme.Radius.tile, inner: Theme.Radius.chipInner)
                PartTile(part: part, tone: group.tone, corners: corners, size: rect.size, text: text,
                         allowsLargeAmount: level == .subcategories && part.share >= VizMetrics.largeAmountMinShare)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .animation(motion.shape, value: motionKey)
                    .vizShade(index: index, visible: isVisible)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: text.label(part)))
                    .accessibilityHidden(!isVisible)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Ключ анимации формы: раскрытие и смена уровня.
private struct TilesMotionKey: Hashable {
    let expandedID: UUID?
    let level: CategoryTilesLevel
}

// MARK: - Плитка категории, «Ещё N», «Без категории»

private struct ItemTile: View {
    let item: CategoryVizItem
    let mode: CategoryVizMode
    let size: CGSize
    let text: VizText

    var body: some View {
        let shape = TileCorners.tile.shape
        ZStack(alignment: .topLeading) {
            switch item {
            case .group(let group):
                shape.fill(VizPaint.fill(group))
                TileLabels(
                    icon: .image(VizText.iconName(group)),
                    name: mode == .stats ? VizText.name(group) : nil,
                    percent: mode == .stats ? VizText.percent(group.share) : nil,
                    amount: text.amount(group.totalMinor),
                    color: VizPaint.label(group),
                    allowsLargeAmount: false,
                    size: size
                )
            case .more(let more):
                shape.fill(VizPaint.moreFill)
                shape.strokeBorder(VizPaint.moreOutline, lineWidth: Theme.Size.hairline)
                TileLabels(
                    icon: .swatches(more),
                    name: mode == .stats ? VizText.moreTitle(more) : nil,
                    percent: mode == .stats ? VizText.percent(more.share) : nil,
                    amount: text.amount(more.totalMinor),
                    color: Theme.ink,
                    allowsLargeAmount: false,
                    size: size
                )
            }
        }
        .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
        .clipShape(shape)
    }
}

/// Тап и озвучка плитки категории.
private struct TileInteraction: ViewModifier {
    let item: CategoryVizItem
    let mode: CategoryVizMode
    /// В раскрытом виде плитки категорий скрыты от касаний и VoiceOver: говорят оттенки.
    let isActive: Bool
    let text: VizText
    let onSelect: (CategoryVizItemID) -> Void

    func body(content: Content) -> some View {
        if isTappable {
            Button { onSelect(item.id) } label: { content }
                .buttonStyle(.pressable())
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityHint(hint)
        } else {
            content
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityHidden(!isActive)
        }
    }

    private var isTappable: Bool {
        guard isActive else { return false }
        switch (mode, item) {
        case (.home, _): return true
        case (.stats, .group(let group)): return group.isExpandable
        case (.stats, .more): return false
        }
    }

    private var label: String {
        switch item {
        case .group(let group): text.label(group)
        case .more(let more): mode == .home ? text.homeMoreLabel(more) : text.statsMoreLabel(more)
        }
    }

    private var hint: Text {
        switch (mode, item) {
        case (.home, .more): Text("home.more.a11y.hint")
        case (.home, .group): Text("home.map.tile.a11y.hint")
        case (.stats, _): Text("stats.map.tile.a11y.hint")
        }
    }
}

// MARK: - Оттенок подкатегории

private struct PartTile: View {
    let part: CategoryVizPart
    let tone: GouacheTone?
    let corners: TileCorners
    let size: CGSize
    let text: VizText
    let allowsLargeAmount: Bool

    var body: some View {
        let shape = corners.shape
        ZStack(alignment: .topLeading) {
            VizPartFill(part: part, tone: tone)
            // На штриховке подписи не читаются: «без подкатегории» описывает список под картой.
            if !part.isUnassigned {
                TileLabels(
                    icon: .image(part.iconName ?? CategoryIconAsset.fallbackName),
                    name: VizText.name(part),
                    percent: VizText.percent(part.share),
                    amount: text.amount(part.totalMinor),
                    color: VizPaint.label(part, tone: tone),
                    allowsLargeAmount: allowsLargeAmount,
                    size: size
                )
            }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
    }
}

// MARK: - Подписи плитки

/// Подписи плитки: из вариантов выбирается первый, что помещается целиком (`ViewThatFits`).
/// Статистика: иконка + доля сверху, имя + сумма снизу → без имени → доля снизу → только иконка.
/// Главная: иконка + сумма → иконка.
private struct TileLabels: View {
    enum Icon {
        case image(String)
        case swatches(CategoryVizMore)
    }

    let icon: Icon
    /// Имя и доля — только в статистике.
    let name: String?
    let percent: String?
    let amount: String
    let color: Color
    /// Крупная сумма (Unbounded 28), если помещается: оттенки раскрытой категории (`04-stats-map-drill`).
    let allowsLargeAmount: Bool
    let size: CGSize

    private var content: CGSize {
        CGSize(
            width: max(size.width - 2 * VizMetrics.tilePadding, 0),
            height: max(size.height - 2 * VizMetrics.tilePadding, 0)
        )
    }

    var body: some View {
        ViewThatFits(in: [.horizontal, .vertical]) {
            if name != nil {
                if allowsLargeAmount {
                    option(top: .iconAndPercent, bottom: .nameAndAmount(large: true))
                }
                option(top: .iconAndPercent, bottom: .nameAndAmount(large: false))
                option(top: .iconAndPercent, bottom: .amount)
                option(top: .icon, bottom: .percent)
                option(top: .iconAndPercent, bottom: .none)
            } else {
                option(top: .icon, bottom: .amount)
            }
            option(top: .icon, bottom: .none)
            Color.clear.frame(width: 0, height: 0)
        }
        .frame(width: content.width, height: content.height, alignment: .topLeading)
        .padding(VizMetrics.tilePadding)
        // Подписи не раздвигают плитку: у плитки уже двух отступов они обрезаются, а не выносят заливку за поле.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }

    private enum Top { case iconAndPercent, icon }
    private enum Bottom: Equatable { case nameAndAmount(large: Bool), amount, percent, none }

    private func option(top: Top, bottom: Bottom) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                iconView
                if top == .iconAndPercent, let percent {
                    Spacer(minLength: 0)
                    percentText(percent)
                }
            }
            if bottom != .none {
                Spacer(minLength: 0)
                bottomView(bottom)
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .image(let name):
            CategoryIconImage(name: name)
                .frame(width: VizMetrics.tileIcon, height: VizMetrics.tileIcon)
        case .swatches(let more):
            VizMiniSwatches(more: more, limit: VizMiniSwatches.count(fitting: content.width))
                .frame(height: VizMetrics.tileIcon)
        }
    }

    private func percentText(_ percent: String) -> some View {
        Text(verbatim: percent)
            .typeStyle(.footnoteStrong)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private func bottomView(_ bottom: Bottom) -> some View {
        switch bottom {
        case .nameAndAmount(let large):
            VStack(alignment: .leading, spacing: 0) {
                if let name {
                    let style: TypeStyle = large ? .callout : .footnoteStrong
                    Text(verbatim: name)
                        .typeStyle(style)
                        .lineLimit(2)
                        .frame(width: content.width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // Имя переносится только по словам: вариант не подходит, если длинное слово шире плитки.
                    Text(verbatim: Self.longestWord(in: name))
                        .typeStyle(style)
                        .fixedSize()
                        .frame(height: 0)
                        .hidden()
                }
                amountText(large: large)
            }
        case .amount:
            amountText(large: false)
        case .percent:
            if let percent { percentText(percent) }
        case .none:
            EmptyView()
        }
    }

    private static func longestWord(in text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        return words.max { $0.count < $1.count } ?? text
    }

    private func amountText(large: Bool) -> some View {
        Text(verbatim: amount)
            .typeStyle(large ? .amountRingTotal : .amountInline)
            .lineLimit(1)
            .fixedSize()
    }
}
