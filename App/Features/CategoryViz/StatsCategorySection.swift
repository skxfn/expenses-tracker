import SwiftUI
import ExpenseCore

/// Раздел «Категории» статистики (`04-stats`, `04-stats-*`): заголовок SF 22 или стеклянный чип
/// «‹ Категории» при раскрытой категории, справа переключатель «Плитки · Полосы · Солнце · Кольцо» (184),
/// подпись «Больше всего — Продукты: 35%», визуализация и список под ней (в «Полосах» списка нет).
/// В раскрытых «Плитках» — переключатель уровня «Категории / Подкатегории».
///
/// Вид и раскрытая категория — снаружи: вид запоминает экран (`SettingsKeys.statsCategoryView`),
/// раскрытие фильтрует остальные блоки статистики («только Продукты»).
struct StatsCategorySection: View {
    let data: CategoryVizData
    @Binding var view: StatsCategoryView
    @Binding var expandedID: UUID?
    /// Период для VoiceOver: «октябрь».
    var periodName: String = ""

    @State private var level: CategoryTilesLevel = .subcategories
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: CategoryVizGroup? { data.expandedGroup(expandedID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            if let caption = VizText.caption(data, expanded: expanded) {
                captionText(caption)
            }
            if view == .tiles, expanded != nil {
                levelSwitch
                    .transition(.opacity)
            }
            visualization
            if view != .strips {
                CategoryVizList(data: data, expandedID: $expandedID)
            }
        }
        .animation(Motion.animation(Motion.vizSwitch, reduceMotion: reduceMotion), value: view)
        .animation(VizMotion(isExpanded: expanded != nil, reduceMotion: reduceMotion).shape, value: expanded?.id)
        .sensoryFeedback(Haptic.selection, trigger: expanded?.id)
    }

    // MARK: Шапка

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack(alignment: .leading) {
                if let expanded {
                    backChip(expanded)
                        .transition(.opacity)
                } else {
                    Text("stats.cats.heading")
                        .typeStyle(.title)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            GlassSegmentedControl(title: "stats.cats.heading", selection: $view, items: [
                .init(value: .tiles, title: "viz.map.name", systemImage: VizSwitcherIcon.tiles),
                .init(value: .strips, title: "viz.strips.name", systemImage: VizSwitcherIcon.strips),
                .init(value: .sun, title: "viz.sun.name", systemImage: VizSwitcherIcon.sun),
                .init(value: .ring, title: "viz.ring.name", systemImage: VizSwitcherIcon.ring),
            ])
            .frame(width: VizMetrics.viewSwitcherWidth)
        }
    }

    /// Стеклянный чип «‹ Категории»: сворачивает раскрытую категорию.
    private func backChip(_ group: CategoryVizGroup) -> some View {
        Button {
            expandedID = nil
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
            .lineLimit(1)
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
                    CategoryTilesView(data: data, expandedID: $expandedID, level: level, periodName: periodName)
                case .strips:
                    CategoryStripsView(data: data, expandedID: $expandedID, periodName: periodName)
                case .sun:
                    CategorySunView(data: data, expandedID: $expandedID, periodName: periodName)
                case .ring:
                    CategoryRingView(data: data, expandedID: $expandedID, periodName: periodName)
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
