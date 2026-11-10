import SwiftUI
import ExpenseCore

/// Раздел «Категории» статистики (`04-stats`, `04-stats-*`): заголовок SF 22 или стеклянный чип
/// «‹ Категории» при раскрытой категории, справа переключатель «Плитки · Полосы · Солнце · Кольцо» (184),
/// подпись «Больше всего — Продукты: 35%», визуализация и список под ней (в «Полосах» списка нет).
/// В раскрытых «Плитках» — переключатель уровня «Категории / Подкатегории».
///
/// Вид и выбор — снаружи: вид запоминает экран (`SettingsKeys.statsCategoryView`), выбор фильтрует остальные
/// блоки статистики («только Продукты»). Выбрать можно любую категорию, «Без категории» и, в раскрытой,
/// подкатегорию: категория с подкатегориями раскрывается до них, а у категории без подкатегорий и «Без категории»
/// визуализация уходит — под «‹ Категории» остаётся их строка, следом журнал трат.
struct StatsCategorySection: View {
    let data: CategoryVizData
    @Binding var view: StatsCategoryView
    @Binding var selection: StatsCategorySelection?
    /// Период для VoiceOver: «октябрь».
    var periodName: String

    @State private var level: CategoryTilesLevel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameter tilesLevel: уровень раскрытых «Плиток» при появлении (по макету — «Подкатегории»).
    init(
        data: CategoryVizData,
        view: Binding<StatsCategoryView>,
        selection: Binding<StatsCategorySelection?>,
        periodName: String = "",
        tilesLevel: CategoryTilesLevel = .subcategories
    ) {
        self.data = data
        _view = view
        _selection = selection
        self.periodName = periodName
        _level = State(initialValue: tilesLevel)
    }

    /// Выбранная категория (у подкатегории — её категория); `nil` — обзор.
    private var focus: CategoryVizGroup? { data.group(for: selection) }
    /// Раскрытая до подкатегорий; у категории без подкатегорий и «Без категории» — `nil`.
    private var expanded: CategoryVizGroup? { data.expandedGroup(focus?.id) }
    /// Выбрана категория без подкатегорий или «Без категории»: вместо визуализации — только её строка.
    private var isCompact: Bool { focus != nil && expanded == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            if !isCompact, let caption = VizText.caption(data, expanded: expanded) {
                captionText(caption)
            }
            if view == .tiles, expanded != nil {
                levelSwitch
                    .transition(.opacity)
            }
            if !isCompact {
                visualization
                    .transition(.opacity)
            }
            if view != .strips || isCompact {
                CategoryVizList(data: data, selection: $selection)
            }
        }
        .animation(Motion.animation(Motion.vizSwitch, reduceMotion: reduceMotion), value: view)
        .animation(VizMotion(isExpanded: focus != nil, reduceMotion: reduceMotion).shape, value: data.resolved(selection))
        .sensoryFeedback(Haptic.selection, trigger: data.resolved(selection))
    }

    // MARK: Шапка

    /// На AX-размерах переключатель уходит под заголовок: рядом с ним «Категории» переносится с дефисом.
    private var header: some View {
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let layout = isStacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.md))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))
        return layout {
            ZStack(alignment: .leading) {
                if let focus {
                    backChip(focus)
                        .transition(.opacity)
                } else {
                    Text("stats.cats.heading")
                        .typeStyle(.title)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .transition(.opacity)
                }
            }
            if !isStacked {
                Spacer(minLength: Theme.Spacing.sm)
            }
            // Без визуализации переключать нечего.
            if !isCompact {
                GlassSegmentedControl(title: "stats.viewSwitch.a11y", selection: $view, items: [
                    .init(value: .tiles, title: "viz.map.name", systemImage: VizSwitcherIcon.tiles),
                    .init(value: .strips, title: "viz.strips.name", systemImage: VizSwitcherIcon.strips),
                    .init(value: .sun, title: "viz.sun.name", systemImage: VizSwitcherIcon.sun),
                    .init(value: .ring, title: "viz.ring.name", systemImage: VizSwitcherIcon.ring),
                ])
                .frame(width: VizMetrics.viewSwitcherWidth)
                .transition(.opacity)
            }
        }
    }

    /// Стеклянный чип «‹ Категории»: снимает выбор, назад к обзору всех категорий.
    private func backChip(_ group: CategoryVizGroup) -> some View {
        Button {
            selection = nil
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
                Text("stats.cats.back")
            }
            .typeStyle(.callout)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minHeight: Theme.Size.chip - Theme.Spacing.sm)
        }
        .glassButtonStyle()
        .accessibilityLabel(Text("stats.cats.back.a11y"))
        .accessibilityHint(Text(verbatim: L10n.format("stats.cats.back.a11y.hint", VizText.name(group))))
    }

    /// «Больше всего — **Продукты: 35%**»: выделение SF 15/600 графитом, остальное — secondary.
    private func captionText(_ caption: AttributedString) -> some View {
        var text = caption
        for run in caption.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].inlinePresentationIntent = nil
            text[run.range].font = TypeStyle.callout.font
            text[run.range].foregroundColor = Theme.ink
        }
        return Text(text)
            .typeStyle(.subheadline)
            .foregroundStyle(Theme.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(0.8)
            .contentTransition(.opacity)
    }

    private var levelSwitch: some View {
        GlassSegmentedControl(title: "viz.level.a11y", selection: $level, items: [
            .init(value: .categories, title: "viz.level.groups"),
            .init(value: .subcategories, title: "viz.level.subs"),
        ])
    }

    // MARK: Визуализация

    private var visualization: some View {
        ZStack {
            Group {
                switch view {
                case .tiles:
                    CategoryTilesView(data: data, selection: $selection, level: level, periodName: periodName)
                case .strips:
                    CategoryStripsView(data: data, selection: $selection, periodName: periodName)
                case .sun:
                    CategorySunView(data: data, selection: $selection, periodName: periodName)
                case .ring:
                    CategoryRingView(data: data, selection: $selection, periodName: periodName)
                }
            }
            .id(view)
            .transition(Motion.transition(Motion.vizSwitchTransition, reduceMotion: reduceMotion))
        }
    }
}

/// Иконки переключателя видов (SF Symbols для хрома, §8 п. 4); подписи VoiceOver — `viz.*.name`.
nonisolated enum VizSwitcherIcon {
    static let tiles = "square.split.bottomrightquarter.fill"
    static let strips = "text.alignleft"
    static let sun = "circle.dotted.circle"
    static let ring = "circle.dashed"
}
