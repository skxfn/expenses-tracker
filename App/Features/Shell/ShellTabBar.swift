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
/// (иконка + подпись 11, активная — пилюля графит 8 %) и отдельный prominent-круг «+» 62 — действие, а не вкладка.
/// Оба — в одном `GlassEffectContainer`. «+» — источник зум-перехода шита записи (`addTransitionID`).
/// Переключение вкладок без анимации (`motionNone`). Текст ограничен AX1: длинная подпись ужимается,
/// крупнее — Large Content Viewer (долгое нажатие).
struct ShellTabBar: View {
    static let addTransitionID = "add"
    /// Иконка вкладки: глиф SF 22 pt ≈ 24 по контуру (DESIGN.md: «иконка 24 + подпись 11»), строка иконки 26.
    private static let iconSize: CGFloat = 22
    private static let iconRowHeight: CGFloat = 26
    private static let iconLabelSpacing: CGFloat = 2
    /// «Календарь», «Статистика» на AX1 ≈ 115 pt при ≈ 95 на вкладку: подпись ужимается, а не обрезается.
    private static let minimumLabelScale: CGFloat = 0.7

    let selection: AppTab
    let addTransition: Namespace.ID
    /// Тап по вкладке; по уже выбранной — корень сам решает (возврат к началу стека).
    let onSelect: (AppTab) -> Void
    let onAdd: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases) { tab in
                        tabButton(tab)
                    }
                }
                .padding(Theme.Spacing.xs)
                .frame(height: Theme.Size.tabBar)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("tabbar.a11y")
                .accessibilityAddTraits(.isTabBar)

                Button(action: onAdd) {
                    Label("tabbar.add.a11y", systemImage: "plus")
                }
                .buttonStyle(.glassCircle(diameter: Theme.Size.addButton, prominent: true))
                .matchedTransitionSource(id: Self.addTransitionID, in: addTransition)
                .accessibilityShowsLargeContentViewer()
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: Self.iconLabelSpacing) {
                Image(systemName: tab.systemImage)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.system(size: Self.iconSize, weight: .medium))
                    .frame(height: Self.iconRowHeight)
                Text(tab.titleKey)
                    .typeStyle(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(Self.minimumLabelScale)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            .foregroundStyle(isSelected ? Theme.ink : Theme.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    Capsule().fill(Theme.tabPill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(tab.titleKey, systemImage: tab.systemImage)
        }
    }
}
