import SwiftUI
import ExpenseCore

/// Геометрия визуализаций категорий (DESIGN.md → Category Visualizations, INTEGRATION §2.1, макеты
/// `01-home`, `02-home-ring`, `04-stats*`). Размеры, которых нет в токенах, сняты с макетов — менять здесь.
nonisolated enum VizMetrics {
    // MARK: Поля

    /// Treemap на главной: 358 × 208.
    static let homeTilesHeight: CGFloat = 208
    /// Treemap в статистике: 358 × 264 (`04-stats`, `04-stats-map-drill`).
    static let statsTilesHeight: CGFloat = 264
    /// «Солнце» и «Кольцо» в статистике: поле 358 × 320.
    static let circleFieldHeight: CGFloat = 320

    // MARK: Плитки

    /// Отступ подписей от края плитки (CSS `.ds-ci` / `.ds-cs`: 10).
    static let tilePadding: CGFloat = 10
    /// Иконка в углу плитки.
    static let tileIcon: CGFloat = 20
    /// Крупная сумма (Unbounded 28) — только у оттенка от этой доли категории (`04-stats-map-drill`:
    /// «Супермаркет 69%» крупно, «Рынок 20%» — 15).
    static let largeAmountMinShare = 0.4
    /// Мини-образец цвета внутри «Ещё N».
    static let miniSwatch: CGFloat = 8
    static let miniSwatchGap: CGFloat = 3
    /// Самая узкая плитка категории: видна, касаема, и в «Ещё N» помещается мини-образец. Без порога при одной
    /// категории на 97 % и больше остальные сжимались в полоску уже зазора. Узкие плитки макета `01-home` (≈ 30)
    /// порог не трогает.
    static let tileMinSide: CGFloat = 2 * tilePadding + miniSwatch

    // MARK: Полосы (design.json → components «Полосы (статистика)»)

    /// Колонка подписей: плашка 36 + 12.
    static let stripLabelInset: CGFloat = 48
    /// Плашка от верха строки.
    static let stripPlaqueTop: CGFloat = 10
    /// Имя от верха строки.
    static let stripNameTop: CGFloat = 5
    /// Зазор имя → «выкраска» (верх «выкраски» — 31 от верха строки).
    static let stripCardSpacing: CGFloat = 6
    /// «Выкраска»: высота 18, слева место под дырку 14, справа и сверху 2, радиусы 8 / 3.
    static let stripCardHeight: CGFloat = 18
    static let stripCardLeading: CGFloat = 14
    static let stripCardPadding: CGFloat = 2
    static let stripCardLeadingRadius: CGFloat = 8
    static let stripCardTrailingRadius: CGFloat = 3
    /// Дырка «выкраски»: 4 × 4, 5 от левого края.
    static let stripHole: CGFloat = 4
    static let stripHoleInset: CGFloat = 5
    /// Сегмент подкатегории: высота 14, радиус 1,5, зазор 2.
    static let stripChipHeight: CGFloat = 14
    static let stripChipRadius: CGFloat = 1.5
    static let stripChipMinWidth: CGFloat = 2

    // MARK: Список под визуализацией (`04-stats`, `-drill`)

    /// Строка категории.
    static let listRow: CGFloat = 48
    /// Плашка подкатегории в раскрытом списке: 28, r 8, иконка 16.
    static let listSubPlaque: CGFloat = 28
    static let listSubPlaqueRadius: CGFloat = 8
    static let listSubPlaqueIcon: CGFloat = 16
    /// Шеврон строки.
    static let chevron: CGFloat = 14

    // MARK: Центр кругов

    /// Иконка категории в центре раскрытого круга.
    static let centerIcon: CGFloat = 26
    /// Итог в центре кольца ужимается до 0,8, если не помещается (длинная сумма, обозначение «BYN»;
    /// INTEGRATION §3.3.1).
    static let centerAmountMinScale: CGFloat = 0.8
    /// На AX-размерах — последний вариант итога (целыми, длинная сумма): ужимается сильнее
    /// (Unbounded 28 на AX1 ≈ 38 pt, × 0,6 ≈ 23).
    static let centerAmountAccessibleMinScale: CGFloat = 0.6
    /// Переключатель видов в статистике (copy.json `stats.cats.heading`: 184 px).
    static let viewSwitcherWidth: CGFloat = 184
}

/// Кольцо категорий: радиусы, скругление концов и подписи-диски.
nonisolated struct RingMetrics: Sendable {
    let inner: CGFloat
    let outer: CGFloat
    /// Скругление концов сегмента.
    let corner: CGFloat
    /// Радиус диска-подписи и расстояние его центра от центра круга.
    let discRadius: CGFloat
    let discOrbit: CGFloat

    /// Главная (`02-home-ring`): R 110 / r 82, концы 5–6, кружки r 18 над сегментами.
    static let home = RingMetrics(inner: 82, outer: 110, corner: 5.5, discRadius: 18, discOrbit: 136)
    /// Статистика (`04-stats-ring`): R ≈ 114 / r ≈ 83; концы на макете прямые, диски 33.
    static let stats = RingMetrics(inner: 83, outer: 114, corner: 1, discRadius: 16.5, discOrbit: 140)
    /// «Солнце», внутреннее кольцо категорий ≈ 71–100, диски 32–36.
    static let sunInner = RingMetrics(inner: 71, outer: 100, corner: 1, discRadius: 17, discOrbit: 140)
    /// «Солнце», внешнее кольцо подкатегорий ≈ 103–109.
    static let sunOuter = RingMetrics(inner: 103, outer: 109, corner: 0.5, discRadius: 17, discOrbit: 140)

    /// Высота поля, в которое помещаются кольцо и диски.
    var fieldHeight: CGFloat { 2 * (discOrbit + discRadius) }

    /// Ширина содержимого в центре круга: внутренний диаметр без полей 6.
    var centerWidth: CGFloat { 2 * inner - Theme.Spacing.md }

    /// Угловой зазор между сегментами: линейный зазор по средней линии кольца.
    func gapAngle(_ gap: CGFloat = Theme.Spacing.segmentGap) -> Double {
        Double(gap / ((inner + outer) / 2))
    }

    /// Минимальный угол между центрами дисков: диаметр + 4.
    var discSeparation: Double { Double((2 * discRadius + Theme.Spacing.xs) / discOrbit) }
}

/// Цвета частей визуализаций. Насыщенный тон — сами визуализации (исключение «Правила тинта»);
/// «Без категории» — нейтраль `CategoryPaint` (§8 п. 10), «Ещё N» — бумага с мини-образцами.
nonisolated enum VizPaint {
    /// Заливка плитки и сегмента категории.
    static func fill(_ group: CategoryVizGroup) -> Color { CategoryPaint.main(group.tone) }

    /// Подпись на заливке категории: графит или бумага по тону; на нейтрали — ink.
    static func label(_ group: CategoryVizGroup) -> Color { group.tone?.labelOnMain ?? Theme.ink }

    /// Заливка части: ступень оттенка; «без подкатегории» рисуется штриховкой (`VizPartFill`).
    static func fill(_ part: CategoryVizPart, tone: GouacheTone?) -> Color {
        guard let tone else { return CategoryPaint.main(nil) }
        return tone.shade(part.shadeStep ?? 0)
    }

    static func label(_ part: CategoryVizPart, tone: GouacheTone?) -> Color {
        guard let tone else { return Theme.ink }
        return part.isUnassigned ? tone.onArea : tone.labelOnShade(part.shadeStep ?? 0)
    }

    /// «Ещё N»: бумажная плитка с контуром.
    static let moreFill = Theme.canvas
    static let moreOutline = Theme.separator
}

/// Заливка части: ступень оттенка или штриховка «без подкатегории».
struct VizPartFill: View {
    let part: CategoryVizPart
    let tone: GouacheTone?

    var body: some View {
        if part.isUnassigned, let tone {
            HatchFill(tone: tone)
        } else {
            Rectangle().fill(VizPaint.fill(part, tone: tone))
        }
    }
}

/// Мини-образцы цветов свёрнутых категорий («Ещё N»): первые `limit` по сумме.
struct VizMiniSwatches: View {
    let more: CategoryVizMore
    var limit = 4

    /// Сколько образцов помещается в ширину `width` (не меньше одного, не больше `maximum`).
    static func count(fitting width: CGFloat, maximum: Int = 4) -> Int {
        let step = VizMetrics.miniSwatch + VizMetrics.miniSwatchGap
        return min(max(Int((width + VizMetrics.miniSwatchGap) / step), 1), maximum)
    }

    var body: some View {
        HStack(spacing: VizMetrics.miniSwatchGap) {
            ForEach(Array(more.groups.prefix(limit).enumerated()), id: \.offset) { _, group in
                RoundedRectangle(cornerRadius: Theme.Radius.chipInner, style: .continuous)
                    .fill(VizPaint.fill(group))
                    .frame(width: VizMetrics.miniSwatch, height: VizMetrics.miniSwatch)
            }
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

// MARK: - Тексты и озвучка

/// Строки визуализаций из каталога (`viz.*`, `stats.*`, `home.*`) и озвучка сумм (`a11y.money`).
/// Данные описываются суммой и долей, не цветом (INTEGRATION §5.3).
nonisolated struct VizText {
    let money: MoneyFormatter

    // MARK: Имена

    static func name(_ group: CategoryVizGroup) -> String {
        group.name ?? String(localized: "stats.legacy.uncategorized")
    }

    static func name(_ part: CategoryVizPart) -> String {
        part.name ?? String(localized: "viz.noSubLegend")
    }

    static func moreTitle(_ more: CategoryVizMore) -> String {
        L10n.format("viz.more", more.groups.count)
    }

    static func moreNames(_ more: CategoryVizMore) -> String {
        more.groups.map(name).joined(separator: ", ")
    }

    static func iconName(_ group: CategoryVizGroup) -> String {
        group.iconName ?? CategoryPaint.uncategorizedIconName
    }

    // MARK: Числа

    /// Сумма в ячейке, плитке, строке: «142,60».
    func amount(_ minor: Int64) -> String { money.string(fromMinor: minor, style: .plain) }

    /// Доля D7: «35%», «<1%».
    static func percent(_ share: Double) -> String { PercentFormatter.string(fromShare: share) }

    /// Сумма для VoiceOver: «142,60 рубля», «5 рублей».
    func spoken(_ minor: Int64) -> String {
        let whole = minor / Money.minorUnitsPerMajor
        return minor % Money.minorUnitsPerMajor == 0
            ? L10n.format("a11y.money", whole)
            : L10n.format("a11y.money.fraction", amount(minor))
    }

    // MARK: Подписи

    /// «Больше всего — Продукты: 35%» / «… — Супермаркет: 69%»; крупнейшая доля без подкатегории или без
    /// категории — «… — без подкатегории: 40%» / «… — без категории: 18%» (`stats.cats.caption.*`).
    static func caption(_ data: CategoryVizData, expanded: CategoryVizGroup?) -> AttributedString? {
        if let expanded {
            guard let part = expanded.largestPart else { return nil }
            if part.isUnassigned { return L10n.attributed("stats.cats.caption.sub.none", percent(part.share)) }
            return L10n.attributed("stats.cats.caption.sub", name(part), percent(part.share))
        }
        guard let group = data.largestGroup else { return nil }
        if group.isUncategorized { return L10n.attributed("stats.cats.caption.group.none", percent(group.share)) }
        return L10n.attributed("stats.cats.caption.group", name(group), percent(group.share))
    }

    /// Вторая строка в списке: «35%» или «6%, подкатегорий нет».
    static func shareLine(_ group: CategoryVizGroup) -> String {
        let share = percent(group.share)
        return group.isUncategorized || group.hasSubcategories ? share : L10n.format("stats.list.noSub", share)
    }

    // MARK: VoiceOver

    /// «Продукты, 142,60 рубля, 35%» — плитка, сегмент, полоса.
    func label(_ group: CategoryVizGroup) -> String {
        [Self.name(group), spoken(group.totalMinor), Self.percent(group.share)].joined(separator: ", ")
    }

    /// Строка списка / полосы: «…, 35% всех трат» или «…, подкатегорий нет».
    func listLabel(_ group: CategoryVizGroup) -> String {
        if group.isExpandable {
            return L10n.format("stats.list.group.a11y", Self.name(group), spoken(group.totalMinor), Self.percent(group.share))
        }
        if group.isUncategorized { return label(group) }
        return L10n.format("stats.strips.noSub.a11y", Self.name(group), spoken(group.totalMinor), Self.percent(group.share))
    }

    /// Часть категории: «Супермаркет, 98,40 рубля, 69% категории».
    func label(_ part: CategoryVizPart) -> String {
        [Self.name(part), spoken(part.totalMinor), L10n.format("stats.list.sub.share", Self.percent(part.share))]
            .joined(separator: ", ")
    }

    /// «Ещё N» в статистике (`viz.more.a11y`).
    func statsMoreLabel(_ more: CategoryVizMore) -> String {
        L10n.format("viz.more.a11y", more.groups.count, Self.moreNames(more), spoken(more.totalMinor), Self.percent(more.share))
    }

    /// «Ещё N» на главной (`home.more.a11y`).
    func homeMoreLabel(_ more: CategoryVizMore) -> String {
        L10n.format("home.more.a11y", more.groups.count, Self.moreNames(more), spoken(more.totalMinor))
    }

    /// Центр раскрытого круга: «Продукты, 142,60 рубля».
    func centerLabel(_ group: CategoryVizGroup) -> String {
        [Self.name(group), spoken(group.totalMinor)].joined(separator: ", ")
    }

    /// «Продукты 35%, Кафе 21%, …» — описание круга, по сумме (`stats.ring.a11y`, `stats.sun.a11y`).
    static func sharesList(_ data: CategoryVizData) -> String {
        data.groups.map { "\(name($0)) \(percent($0.share))" }.joined(separator: ", ")
    }

    /// Порядок VoiceOver по сумме: чем больше сумма, тем раньше (`accessibilitySortPriority`).
    static func sortPriority(_ index: Int, count: Int) -> Double { Double(count - index) }
}

extension View {
    /// Подписи на цветных частях: плотные места ограничены AX1 (INTEGRATION §6).
    func vizDynamicTypeLimit() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
