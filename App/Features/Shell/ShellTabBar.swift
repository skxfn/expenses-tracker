import SwiftUI

extension AppTab: Identifiable {
    var id: Self { self }

    /// Подпись вкладки — она же имя для VoiceOver.
    var titleKey: LocalizedStringKey {
        switch self {
        case .expenses: "tabbar.expenses"
        case .calendar: "tabbar.calendar"
        case .statistics: "tabbar.statistics"
        }
    }

    /// SF Symbol вкладки (§8 п. 4); у выбранной — вариант `.fill`, если он есть.
    var systemImage: String {
        switch self {
        case .expenses: "house"
        case .calendar: "calendar"
        case .statistics: "chart.pie"
        }
    }
}

/// Таб-бар (DESIGN.md → Navigation, §8 п. 5, вариант «в»): стеклянная капсула 62 с тремя вкладками
/// (иконка + подпись 11) и отдельный prominent-круг «+» 62 — действие, а не вкладка.
/// Бар с линзой — в `GlassEffectContainer`, «+» — рядом, вне него: он источник зум-перехода шита записи (`addTransitionID`).
/// Активная вкладка — стеклянная линза с тинтом графит 8 %, как выделение системного таб-бара iOS 26:
/// касание поднимает линзу над вкладкой под пальцем, линза едет за пальцем, отпускание выбирает вкладку,
/// и линза пружиной садится на неё; переход пальца на другую вкладку — тактильный отклик выбора.
/// Вкладки — не `Button`: касания ведёт один жест ряда (кнопка под пальцем и жест выбирали бы дважды),
/// VoiceOver выбирает действием элемента. Содержимое вкладок переключается без анимации (`motionNone`).
/// Reduce Motion: линза не летит и не растёт — проявляется у вкладки под пальцем или у выбранной.
/// Текст ограничен AX1: длинная подпись ужимается, крупнее — Large Content Viewer (долгое нажатие).
struct ShellTabBar: View {
    static let addTransitionID = "add"
    /// Иконка вкладки: глиф SF 22 pt ≈ 24 по контуру (DESIGN.md: «иконка 24 + подпись 11»), строка иконки 26.
    private static let iconSize: CGFloat = 22
    private static let iconRowHeight: CGFloat = 26
    private static let iconLabelSpacing: CGFloat = 2
    /// «Календарь», «Статистика» на AX1 ≈ 115 pt при ≈ 95 на вкладку: подпись ужимается, а не обрезается.
    private static let minimumLabelScale: CGFloat = 0.7
    /// Поднятая линза дорастает до краёв капсулы (54 → 62), вкладка под пальцем крупнее — как у системной.
    private static let liftedLensScale = Theme.Size.tabBar / (Theme.Size.tabBar - 2 * Theme.Spacing.xs)
    private static let liftedItemScale: CGFloat = 1.15
    /// Стёкла контейнера не сливаются, даже когда бар вздувается от касания (`.interactive()`).
    private static let glassMergeSpacing: CGFloat = 0

    let selection: AppTab
    let addTransition: Namespace.ID
    /// Выбор вкладки; по уже выбранной — корень сам решает (возврат к началу стека).
    let onSelect: (AppTab) -> Void
    let onAdd: () -> Void

    /// Касание ряда вкладок; `nil` — ряд не трогают.
    private struct Touch: Equatable {
        let startX: CGFloat
        let startTab: AppTab
        var x: CGFloat
        /// Вкладка под пальцем.
        var tab: AppTab
    }

    @State private var touch: Touch?
    @State private var rowWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            GlassEffectContainer(spacing: Self.glassMergeSpacing) {
                tabs
                    .padding(Theme.Spacing.xs)
                    .frame(height: Theme.Size.tabBar)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }

            // «+» — вне `GlassEffectContainer`: в iOS 27 источник зума внутри контейнера не находится
            // («zoom transition from a nil view»), и шит открывается запасным переходом без зума.
            Button(action: onAdd) {
                Label("tabbar.add.a11y", systemImage: "plus")
            }
            .buttonStyle(.glassCircle(diameter: Theme.Size.addButton, prominent: true))
            .matchedTransitionSource(id: Self.addTransitionID, in: addTransition)
            .accessibilityShowsLargeContentViewer()
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .sensoryFeedback(Haptic.selection, trigger: touch?.tab) { old, new in old != nil && new != nil }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabItem(tab)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("tabbar.a11y")
        .accessibilityAddTraits(.isTabBar)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .contentShape(Rectangle())
        .gesture(selectionGesture)
        // Линза — вне контейнера VoiceOver: внутри него она становится пустой «кнопкой» даже со `.accessibilityHidden`.
        .background(alignment: .leading) {
            lens
        }
    }

    // MARK: Линза

    /// Вкладка, над которой линза: под пальцем или выбранная.
    private var activeTab: AppTab { touch?.tab ?? selection }
    private var isLifted: Bool { touch != nil && !reduceMotion }
    private var lensAnimation: Animation { reduceMotion ? Motion.reduced : Motion.morph }
    private var slotWidth: CGFloat { rowWidth / CGFloat(AppTab.allCases.count) }

    private func slotX(_ tab: AppTab) -> CGFloat {
        CGFloat(AppTab.allCases.firstIndex(of: tab) ?? 0) * slotWidth
    }

    /// Левый край линзы: при касании — за пальцем от вкладки, где палец опустился, иначе — у выбранной.
    private var lensX: CGFloat {
        guard let touch, !reduceMotion else { return slotX(activeTab) }
        let x = slotX(touch.startTab) + touch.x - touch.startX
        return min(max(x, 0), max(rowWidth - slotWidth, 0))
    }

    /// Одна линза на весь ряд: выбор вкладки и подъём анимирует пружина `morph`, за пальцем — без анимации
    /// (и при переходе пальца на другую вкладку). При Reduce Motion у каждой вкладки своя линза: старая гаснет,
    /// новая проявляется.
    private var lens: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.clear)
                .frame(width: slotWidth)
                .glassEffect(.regular.tint(Theme.tabPill), in: .capsule)
                .scaleEffect(isLifted ? Self.liftedLensScale : 1)
                .offset(x: lensX)
                .id(reduceMotion ? activeTab : nil)
                .transition(.opacity)
        }
        .animation(lensAnimation, value: reduceMotion ? activeTab : selection)
        .animation(lensAnimation, value: isLifted)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Вкладка

    private func tabItem(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        let isActive = tab == activeTab
        return VStack(spacing: Self.iconLabelSpacing) {
            Image(systemName: tab.systemImage)
                .symbolVariant(isActive ? .fill : .none)
                .font(.system(size: Self.iconSize, weight: .medium))
                .frame(height: Self.iconRowHeight)
            Text(tab.titleKey)
                .typeStyle(.caption)
                .lineLimit(1)
                .minimumScaleFactor(Self.minimumLabelScale)
                .padding(.horizontal, Theme.Spacing.xs)
        }
        .foregroundStyle(isActive ? Theme.ink : Theme.secondary)
        .scaleEffect(isLifted && isActive ? Self.liftedItemScale : 1)
        .animation(lensAnimation, value: isActive)
        .animation(lensAnimation, value: isLifted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Рамка VoiceOver — вся доля вкладки, как у кнопки, а не только иконка с подписью.
        .contentShape(.accessibility, Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tab.titleKey))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect(tab) }
        .accessibilityShowsLargeContentViewer {
            Label(tab.titleKey, systemImage: tab.systemImage)
        }
    }

    // MARK: Жест

    private func tab(at x: CGFloat) -> AppTab {
        let tabs = AppTab.allCases
        guard slotWidth > 0 else { return selection }
        let index = Int((x / slotWidth).rounded(.down))
        return tabs[min(max(index, 0), tabs.count - 1)]
    }

    /// Касание поднимает линзу над вкладкой, палец ведёт её по ряду, отпускание выбирает вкладку под пальцем.
    /// Палец, ушедший с бара выше его высоты, — отмена: линза возвращается к выбранной.
    private var selectionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let hovered = tab(at: value.location.x)
                if touch == nil {
                    let start = tab(at: value.startLocation.x)
                    touch = Touch(startX: value.startLocation.x, startTab: start, x: value.location.x, tab: hovered)
                } else {
                    touch?.x = value.location.x
                    touch?.tab = hovered
                }
            }
            .onEnded { value in
                let target = touch?.tab ?? tab(at: value.location.x)
                touch = nil
                guard abs(value.translation.height) <= Theme.Size.tabBar else { return }
                onSelect(target)
            }
    }
}
