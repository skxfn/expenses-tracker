#if DEBUG
import SwiftUI
import ExpenseCore

/// Вкладки спайка (как в макете: «Траты · Календарь · Статистика»).
enum SpikeTab: Hashable, CaseIterable {
    case feed, calendar, statistics

    var title: String {
        switch self {
        case .feed: "Траты"
        case .calendar: "Календарь"
        case .statistics: "Статистика"
        }
    }

    func systemImage(selected: Bool) -> String {
        switch self {
        case .feed: selected ? "house.fill" : "house"
        case .calendar: "calendar"
        case .statistics: "chart.pie"
        }
    }
}

private struct SpikePlaceholder: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .typeStyle(.headline)
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AuraBackground(tones: [.kobalt, .ametist]).ignoresSafeArea())
    }
}

// MARK: - Вариант (а): системный TabView + свой круг «+» поверх

struct TabBarSystemSpike: View {
    @State private var tab = SpikeTab.feed
    @State private var isAddPresented = false
    @Namespace private var zoom

    var body: some View {
        TabView(selection: $tab) {
            Tab(SpikeTab.feed.title, systemImage: SpikeTab.feed.systemImage(selected: true), value: SpikeTab.feed) {
                FeedSpikeContent()
            }
            Tab(SpikeTab.calendar.title, systemImage: SpikeTab.calendar.systemImage(selected: false), value: SpikeTab.calendar) {
                SpikePlaceholder(title: SpikeTab.calendar.title)
            }
            Tab(SpikeTab.statistics.title, systemImage: SpikeTab.statistics.systemImage(selected: false), value: SpikeTab.statistics) {
                SpikePlaceholder(title: SpikeTab.statistics.title)
            }
        }
        .tint(Theme.ink)
        .overlay(alignment: .bottomTrailing) {
            Button("Новая трата", systemImage: "plus") { isAddPresented = true }
                .buttonStyle(.glassCircle(diameter: Theme.Size.addButton, prominent: true))
                .matchedTransitionSource(id: "add", in: zoom)
                .padding(.trailing, Theme.Spacing.screen)
        }
        .sheet(isPresented: $isAddPresented) {
            AddSheetSpikeContent()
                .navigationTransition(.zoom(sourceID: "add", in: zoom))
        }
    }
}

// MARK: - Вариант (в): свой бар в GlassEffectContainer, системная панель скрыта

struct TabBarCustomSpike: View {
    var autoPresentAdd = false

    @State private var tab = SpikeTab.feed
    @State private var isAddPresented = false
    @Namespace private var zoom

    var body: some View {
        TabView(selection: $tab) {
            Tab(SpikeTab.feed.title, systemImage: SpikeTab.feed.systemImage(selected: false), value: SpikeTab.feed) {
                FeedSpikeContent()
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab(SpikeTab.calendar.title, systemImage: SpikeTab.calendar.systemImage(selected: false), value: SpikeTab.calendar) {
                SpikePlaceholder(title: SpikeTab.calendar.title)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab(SpikeTab.statistics.title, systemImage: SpikeTab.statistics.systemImage(selected: false), value: SpikeTab.statistics) {
                SpikePlaceholder(title: SpikeTab.statistics.title)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SpikeTabBar(selection: $tab, zoom: zoom) { isAddPresented = true }
        }
        .sheet(isPresented: $isAddPresented) {
            AddSheetSpikeContent()
                .navigationTransition(.zoom(sourceID: "add", in: zoom))
        }
        .task {
            guard autoPresentAdd else { return }
            try? await Task.sleep(for: .milliseconds(700))
            isAddPresented = true
        }
    }
}

/// Свой таб-бар: стеклянная капсула 62 с тремя вкладками (иконка + подпись 11, активная — пилюля графит 8 %)
/// и отдельный prominent-круг «+» 62. Оба — в одном `GlassEffectContainer`.
struct SpikeTabBar: View {
    @Binding var selection: SpikeTab
    let zoom: Namespace.ID
    let onAdd: () -> Void

    @Namespace private var pill

    var body: some View {
        GlassEffectContainer(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                HStack(spacing: 0) {
                    ForEach(SpikeTab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                .padding(Theme.Spacing.xs)
                .frame(height: Theme.Size.tabBar)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isTabBar)

                Button("Новая трата", systemImage: "plus", action: onAdd)
                    .buttonStyle(.glassCircle(diameter: Theme.Size.addButton, prominent: true))
                    .matchedTransitionSource(id: "add", in: zoom)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, Theme.Spacing.screen)
    }

    private func tabButton(_ tab: SpikeTab) -> some View {
        let isSelected = tab == selection
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage(selected: isSelected))
                    .font(.system(size: 22, weight: .medium))
                    .frame(height: 26)
                Text(verbatim: tab.title)
                    .typeStyle(.caption)
            }
            .foregroundStyle(isSelected ? Theme.ink : Theme.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.tabPill)
                        .matchedGeometryEffect(id: "tab", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
    }
}

// MARK: - Шит записи с зумом из «+»

struct AddSheetSpike: View {
    var body: some View {
        TabBarCustomSpike(autoPresentAdd: true)
    }
}

/// Шит «Новая трата» для спайка: сумма Unbounded 60 в системном поле `.decimalPad`,
/// быстрые суммы — `ToolbarItemGroup(placement: .keyboard)`, аура выбранной категории у нижнего края.
struct AddSheetSpikeContent: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount = "12,50"
    @State private var quickSumCount = 0
    @FocusState private var isAmountFocused: Bool

    private let tone = GouacheTone.shalfey
    private let quickSums = [5, 10, 20, 50, 100]
    /// `-spikeKeys group` — системная группа (одна общая капсула) вместо своих отдельных капсул.
    private let separateKeys = UserDefaults.standard.string(forKey: "spikeKeys") != "group"

    private func quickSumButton(_ value: Int) -> some View {
        Button {
            quickSumCount += 1
        } label: {
            Text(verbatim: "+\(value)")
                .typeStyle(.amountInline)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    TextField(text: $amount, prompt: Text(verbatim: "0")) {
                        Text(verbatim: "Сумма")
                    }
                    .typeStyle(.amountDisplay)
                    .foregroundStyle(Theme.ink)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .fixedSize()
                    .focused($isAmountFocused)
                    Text(verbatim: "Br").typeStyle(.currencyDisplay).foregroundStyle(Theme.secondary)
                }
                Text(verbatim: "Продукты · Супермаркет").typeStyle(.callout).foregroundStyle(Theme.secondary)
                HStack(spacing: Theme.Spacing.md) {
                    Button("Ещё одна") {}.buttonStyle(.glassCapsule())
                    Button("Сохранить") {}.buttonStyle(.glassCapsule(.prominent))
                }
                .padding(.horizontal, Theme.Spacing.screen)
                Spacer()
            }
            .padding(.top, Theme.Spacing.xl)
            .sheetHeader("Новая трата", onClose: { dismiss() })
            .toolbar {
                if separateKeys {
                    // Свой ряд стеклянных клавиш 44 на всю ширину; общий фон панели снят.
                    ToolbarItem(placement: .keyboard) {
                        GlassEffectContainer(spacing: Theme.Spacing.sm) {
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(quickSums, id: \.self) { value in
                                    quickSumButton(value)
                                        .frame(maxWidth: .infinity, minHeight: Theme.Size.chip)
                                        .glass(.key)
                                }
                            }
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    // Системная группа: iOS 26 кладёт все пункты в одну стеклянную капсулу.
                    ToolbarItemGroup(placement: .keyboard) {
                        ForEach(quickSums, id: \.self) { value in
                            quickSumButton(value)
                        }
                    }
                }
            }
            .sensoryFeedback(Haptic.light, trigger: quickSumCount)
        }
        .presentationBackground {
            AuraBackground(tones: [tone], edge: .bottom, base: Theme.canvasElevated)
        }
        .task { isAmountFocused = true }
    }
}
#endif
