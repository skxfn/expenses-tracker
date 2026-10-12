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

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
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

// MARK: - Вариант (б): системный TabView, «+» — вкладка `Tab(role: .search)`

/// «+» — закреплённая вкладка с ролью поиска (отдельный круг справа). Выбор этой вкладки перехватывается
/// привязкой: вкладка не меняется, открывается шит. Во «Календаре» — пуш со скрытым таб-баром.
struct TabBarNativeSpike: View {
    enum Value: Hashable {
        case tab(SpikeTab)
        case add
    }

    @State private var tab = SpikeTab.feed
    @State private var isAddPresented = false

    private var selection: Binding<Value> {
        Binding {
            .tab(tab)
        } set: { value in
            switch value {
            case .tab(let newTab): tab = newTab
            case .add: isAddPresented = true
            }
        }
    }

    var body: some View {
        TabView(selection: selection) {
            Tab(SpikeTab.feed.title, systemImage: "house", value: Value.tab(.feed)) {
                FeedSpikeContent()
            }
            Tab(SpikeTab.calendar.title, systemImage: "calendar", value: Value.tab(.calendar)) {
                NavigationStack {
                    SpikePlaceholder(title: SpikeTab.calendar.title)
                        .overlay(alignment: .top) {
                            NavigationLink("Пуш без таб-бара") {
                                SpikePlaceholder(title: "Пуш")
                                    .toolbarVisibility(.hidden, for: .tabBar)
                            }
                            .padding(.top, 80)
                        }
                }
            }
            Tab(SpikeTab.statistics.title, systemImage: "chart.pie", value: Value.tab(.statistics)) {
                SpikePlaceholder(title: SpikeTab.statistics.title)
            }
            Tab("Новая трата", systemImage: "plus", value: Value.add, role: .search) {
                SpikePlaceholder(title: "Вкладка «+» (не должна открываться)")
            }
        }
        .tint(Theme.ink)
        .tabBarMinimizeBehavior(.never)
        .sheet(isPresented: $isAddPresented) {
            AddSheetSpikeContent()
        }
    }
}

// MARK: - Вариант (в) с линзой: касание, перетаскивание, пружина

/// Свой бар с линзой выделения как у системного: касание поднимает линзу над вкладкой, линза едет за пальцем,
/// отпускание выбирает вкладку под пальцем и линза пружиной садится на неё.
/// `-spikeLens fill|glass|clear`: покой — пилюля графит 8 % (`fill`), стекло с тинтом в общем контейнере (`glass`),
/// пилюля + прозрачное стекло поверх бара при касании (`clear`).
struct TabBarLensSpike: View {
    @State private var tab = SpikeTab.feed

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SpikeTab.allCases, id: \.self) { item in
                Tab(item.title, systemImage: item.systemImage(selected: false), value: item) {
                    Group {
                        if item == .feed { FeedSpikeContent() } else { SpikePlaceholder(title: item.title) }
                    }
                    .toolbarVisibility(.hidden, for: .tabBar)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SpikeLensBar(selection: $tab)
        }
    }
}

struct SpikeLensBar: View {
    @Binding var selection: SpikeTab

    @State private var rowWidth: CGFloat = 0
    /// Палец на ряду: x в координатах ряда; `nil` — не касаются.
    @State private var dragX: CGFloat?
    @State private var touchStartX: CGFloat = 0
    @State private var lensStartX: CGFloat = 0
    @State private var hovered: SpikeTab?
    @Namespace private var glassNamespace

    private let mode = UserDefaults.standard.string(forKey: "spikeLens") ?? "fill"
    private let tabs = SpikeTab.allCases
    private let spring = Animation.spring(duration: 0.4, bounce: 0.2)

    private let containerSpacing = CGFloat(UserDefaults.standard.double(forKey: "spikeSpacing").nonZero ?? Double(Theme.Spacing.md))

    var body: some View {
        GlassEffectContainer(spacing: containerSpacing) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack(alignment: .leading) {
                    if mode == "glass" { glassLens }
                    row
                }
                .padding(Theme.Spacing.xs)
                .frame(height: Theme.Size.tabBar)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("bar", in: glassNamespace)

                Button("Новая трата", systemImage: "plus") {}
                    .buttonStyle(.glassCircle(diameter: Theme.Size.addButton, prominent: true))
            }
        }
        .overlay(alignment: .leading) {
            if mode == "clear" { clearLens }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .sensoryFeedback(Haptic.selection, trigger: hovered)
    }

    private var itemWidth: CGFloat { rowWidth / CGFloat(tabs.count) }
    private var isLifted: Bool { dragX != nil }

    /// Левый край линзы: за пальцем при касании, иначе — у выбранной вкладки.
    private var lensX: CGFloat {
        let index = CGFloat(tabs.firstIndex(of: selection) ?? 0)
        let x = dragX.map { lensStartX + $0 - touchStartX } ?? index * itemWidth
        return min(max(x, 0), max(rowWidth - itemWidth, 0))
    }

    private var row: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                item(tab)
            }
        }
        .background(alignment: .leading) {
            if mode != "glass" && mode != "morph" {
                Capsule()
                    .fill(Theme.tabPill)
                    .frame(width: itemWidth)
                    .scaleEffect(isLifted && mode == "fill" ? 1.12 : 1)
                    .opacity(isLifted && mode == "clear" ? 0 : 1)
                    .offset(x: lensX)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private var glassLens: some View {
        Capsule()
            .fill(.clear)
            .frame(width: itemWidth)
            .glassEffect(.regular.tint(Theme.tabPill).interactive(), in: .capsule)
            .glassEffectID("lens", in: glassNamespace)
            .scaleEffect(isLifted ? 1.12 : 1)
            .offset(x: lensX)
    }

    private var clearLens: some View {
        Capsule()
            .fill(.clear)
            .frame(width: itemWidth + 8, height: Theme.Size.tabBar - 4)
            .glassEffect(isLifted ? .clear.interactive() : .identity, in: .capsule)
            .offset(x: lensX + Theme.Spacing.xs - 4)
            .allowsHitTesting(false)
    }

    private func item(_ tab: SpikeTab) -> some View {
        let isActive = (hovered ?? selection) == tab
        return VStack(spacing: 2) {
            Image(systemName: tab.systemImage(selected: isActive))
                .font(.system(size: 22, weight: .medium))
                .frame(height: 26)
            Text(verbatim: tab.title)
                .typeStyle(.caption)
        }
        .foregroundStyle(isActive ? Theme.ink : Theme.secondary)
        .scaleEffect(isLifted && hovered == tab ? 1.15 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if mode == "morph" && isActive {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.tint(Theme.tabPill).interactive(), in: .capsule)
                    .glassEffectID("lens", in: glassNamespace)
                    .scaleEffect(isLifted ? 1.12 : 1)
            }
        }
    }

    private func tab(at x: CGFloat) -> SpikeTab {
        guard itemWidth > 0 else { return selection }
        let index = Int(x / itemWidth)
        return tabs[min(max(index, 0), tabs.count - 1)]
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragX == nil {
                    let touched = tab(at: value.startLocation.x)
                    touchStartX = value.startLocation.x
                    lensStartX = CGFloat(tabs.firstIndex(of: touched) ?? 0) * itemWidth
                    withAnimation(spring) {
                        dragX = value.location.x
                        hovered = touched
                    }
                } else {
                    dragX = value.location.x
                    let over = tab(at: value.location.x)
                    if over != hovered {
                        withAnimation(.snappy(duration: 0.2)) { hovered = over }
                    }
                }
            }
            .onEnded { value in
                let target = tab(at: value.location.x)
                withAnimation(spring) {
                    selection = target
                    dragX = nil
                    hovered = nil
                }
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
                    Text(verbatim: "\u{20C5}").typeStyle(.currencyDisplay).foregroundStyle(Theme.secondary)
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
