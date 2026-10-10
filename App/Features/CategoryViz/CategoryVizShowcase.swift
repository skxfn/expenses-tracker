#if DEBUG
import SwiftUI
import ExpenseCore

/// DEBUG-витрина визуализаций категорий: `-debugShowcase viz` (страница `ShowcasePage.viz`).
/// Аргументы для скриншотов без касаний (панель выбора тогда скрыта):
/// - `-vizView home|homeRing|tiles|strips|sun|ring` — что показать;
/// - `-vizData demo|many|uncategorized|few|one|empty` — набор данных (по умолчанию `demo`, как на макетах);
/// - `-vizExpand YES` — раскрыть первую раскрываемую категорию; `-vizLevel categories` — уровень плиток;
/// - `-vizToggle YES` — раскрывать и сворачивать каждые 2,5 с (проверка анимаций).
struct CategoryVizShowcase: View {
    @State private var dataset: VizDemoDataset
    @State private var page: VizShowcasePage
    @State private var statsView: StatsCategoryView
    @State private var expandedID: UUID?
    private let isScreenshot: Bool
    private let toggles: Bool

    init(defaults: UserDefaults = .standard) {
        let requested = defaults.string(forKey: "vizView").flatMap(VizShowcasePage.init(rawValue:))
        let dataset = defaults.string(forKey: "vizData").flatMap(VizDemoDataset.init(rawValue:)) ?? .demo
        let page = requested ?? .tiles
        _dataset = State(initialValue: dataset)
        _page = State(initialValue: page)
        _statsView = State(initialValue: page.statsView ?? .tiles)
        let expands = defaults.bool(forKey: "vizExpand")
        _expandedID = State(initialValue: expands ? VizDemo.data(dataset).groups.first(where: \.isExpandable)?.id : nil)
        isScreenshot = requested != nil
        toggles = defaults.bool(forKey: "vizToggle")
    }

    private var data: CategoryVizData { VizDemo.data(dataset) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if !isScreenshot {
                    controls
                }
                content
            }
            .padding(.top, isScreenshot ? Theme.Spacing.xl : 0)
        }
        .background { background.ignoresSafeArea() }
        .toolbar(isScreenshot ? .hidden : .visible, for: .navigationBar)
        .navigationTitle(Text(verbatim: "Визуализации категорий"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: dataset) { expandedID = nil }
        .onChange(of: page) { _, page in
            if let view = page.statsView { statsView = view }
        }
        .task(id: toggles) {
            guard toggles else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                expandedID = expandedID == nil ? data.groups.first(where: \.isExpandable)?.id : nil
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        if page == .homeRing {
            AuraBackground(tones: auraTones)
        } else {
            Theme.canvas
        }
    }

    private var auraTones: [GouacheTone] {
        data.groups.compactMap(\.tone).prefix(3).map { $0 }
    }

    // MARK: Выбор

    private var controls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Picker(selection: $dataset) {
                ForEach(VizDemoDataset.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text(verbatim: "Данные")
            }
            .pickerStyle(.menu)
            Picker(selection: $page) {
                ForEach(VizShowcasePage.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text(verbatim: "Вид")
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, Theme.Spacing.screen)
    }

    // MARK: Содержимое

    @ViewBuilder
    private var content: some View {
        switch page {
        case .home:
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                AmountText(
                    text: MoneyFormatter(currencyCode: "BYN", locale: .app).string(fromMinor: data.totalMinor, style: .plain),
                    value: Double(data.totalMinor),
                    size: .total,
                    currency: "Br"
                )
                CategoryTilesView(homeData: data, periodName: "октябрь") { selected = $0 }
                selection
            }
            .padding(Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.sm)
            .paperSheetBackground()
        case .homeRing:
            VStack(spacing: Theme.Spacing.md) {
                HomeCategoryRing(data: data, periodName: "октябрь", onSelect: { selected = $0 }) {
                    Text(VizDemo.phrase)
                }
                selection
            }
            .padding(.horizontal, Theme.Spacing.screen)
        case .tiles, .strips, .sun, .ring:
            StatsCategorySection(data: data, view: $statsView, expandedID: $expandedID, periodName: "октябрь")
                .padding(Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.sm)
                .paperSheetBackground()
        }
    }

    @State private var selected: CategoryVizItemID?

    @ViewBuilder
    private var selection: some View {
        if !isScreenshot {
            Text(verbatim: "Колбэк: \(selected.map { "\($0)" } ?? "—")")
                .typeStyle(.footnote)
                .foregroundStyle(Theme.secondary)
        }
    }
}

enum VizShowcasePage: String, CaseIterable {
    case home, homeRing, tiles, strips, sun, ring

    var title: String {
        switch self {
        case .home: "Гл.: плитки"
        case .homeRing: "Гл.: кольцо"
        case .tiles: "Плитки"
        case .strips: "Полосы"
        case .sun: "Солнце"
        case .ring: "Кольцо"
        }
    }

    var statsView: StatsCategoryView? {
        switch self {
        case .home, .homeRing: nil
        case .tiles: .tiles
        case .strips: .strips
        case .sun: .sun
        case .ring: .ring
        }
    }
}

// MARK: - Демо-данные

enum VizDemoDataset: String, CaseIterable {
    /// Как на макетах `04-stats*`: 8 категорий, 412,30, 18 трат.
    case demo
    /// 15 категорий: мелкие сворачиваются в «Ещё N», есть «Без категории».
    case many
    /// Демо + «Без категории» и траты «без подкатегории» в Продуктах.
    case uncategorized
    /// Мало категорий.
    case few
    /// Одна категория.
    case one
    /// Пусто.
    case empty

    var title: String {
        switch self {
        case .demo: "Как на макетах"
        case .many: "15 категорий, «Ещё N»"
        case .uncategorized: "«Без категории», штриховка"
        case .few: "Две категории"
        case .one: "Одна категория"
        case .empty: "Пусто"
        }
    }
}

enum VizDemo {
    static var phrase: AttributedString {
        var text = L10n.attributed("home.compare", "38\u{00A0}Br", String(localized: "home.compare.month.current"))
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].inlinePresentationIntent = nil
            text[run.range].font = TypeStyle.footnote.font.weight(.semibold)
            text[run.range].foregroundColor = Theme.ink
        }
        return text
    }

    private static let cache: [VizDemoDataset: CategoryVizData] = Dictionary(
        uniqueKeysWithValues: VizDemoDataset.allCases.map { ($0, build($0)) }
    )

    static func data(_ dataset: VizDemoDataset) -> CategoryVizData { cache[dataset]! }

    private struct Group {
        let name: String
        let icon: String
        let tone: GouacheTone
        var subs: [(name: String, icon: String, amounts: [Int64])] = []
        var direct: [Int64] = []
    }

    private static let mockup: [Group] = [
        Group(name: "Продукты", icon: "basket-fill", tone: .shalfey, subs: [
            ("Супермаркет", "shopping-cart-1-fill", [5_620, 4_220]),
            ("Рынок", "apple-fruit-fill", [2_820]),
            ("Хлеб и выпечка", "bread-fill", [1_600]),
        ]),
        Group(name: "Кафе", icon: "fork-knife-fill", tone: .abrikos, subs: [
            ("Обеды", "fork-knife-fill", [5_050]),
            ("Кофе", "teacup-fill", [1_900]),
            ("Ужины", "wineglass-fill", [1_690]),
        ]),
        Group(name: "Развлечения", icon: "celebrate-fill", tone: .ametist, subs: [
            ("Кино", "movie-fill", [2_600]),
            ("Концерты", "music-fill", [1_800]),
        ]),
        Group(name: "Транспорт", icon: "bus-fill", tone: .kobalt, subs: [
            ("Такси", "car-fill", [2_200]),
            ("Метро", "train-fill", [1_600]),
        ]),
        Group(name: "Подписки", icon: "repeat-fill", tone: .ultramarin, subs: [
            ("Музыка", "music-fill", [1_499]),
            ("Облако", "laptop-fill", [900]),
            ("Видео", "tv-1-fill", [800]),
        ]),
        Group(name: "Связь", icon: "wifi-fill", tone: .tseruleum, subs: [
            ("Мобильный", "cellphone-fill", [1_300]),
            ("Интернет", "signal-fill", [1_200]),
        ]),
        Group(name: "Здоровье", icon: "capsule-fill", tone: .kinovar, subs: [
            ("Аптека", "first-aid-kit-fill", [1_870]),
        ]),
        Group(name: "Другое", icon: "more-3-fill", tone: .grafit, direct: [2_561]),
    ]

    private static let extra: [Group] = [
        Group(name: "Дом", icon: "home-4-fill", tone: .umbra, direct: [5_400]),
        Group(name: "Одежда", icon: "t-shirt-fill", tone: .pion, direct: [6_900]),
        Group(name: "Подарки", icon: "gift-fill", tone: .krapplak, subs: [("Друзьям", "gift-fill", [900])]),
        Group(name: "Образование", icon: "mortarboard-fill", tone: .okhra, direct: [700]),
        Group(name: "Спорт", icon: "barbell-fill", tone: .olivka, direct: [600]),
        Group(name: "Питомцы", icon: "paw-fill", tone: .viridon, direct: [400]),
        Group(name: "Красота", icon: "lipstick-fill", tone: .slanets, direct: [300]),
    ]

    private static func build(_ dataset: VizDemoDataset) -> CategoryVizData {
        var groups: [Group]
        var uncategorized: [Int64] = []
        switch dataset {
        case .demo:
            groups = mockup
        case .many:
            groups = mockup + extra
            uncategorized = [1_250]
        case .uncategorized:
            groups = mockup
            groups[0].direct = [2_400]
            uncategorized = [3_000, 650]
        case .few:
            groups = [mockup[1], mockup[3]]
        case .one:
            groups = [mockup[0]]
        case .empty:
            groups = []
        }
        return make(groups, uncategorized: uncategorized)
    }

    private static func make(_ groups: [Group], uncategorized: [Int64]) -> CategoryVizData {
        var counter = 0
        func nextID() -> UUID {
            counter += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", counter))!
        }
        let calendar = Calendar.current
        let now = Date.now
        var entries: [CategoryCatalogSnapshot.Entry] = []
        var records: [ExpenseRecord] = []
        for group in groups {
            let groupID = nextID()
            entries.append(.init(id: groupID, name: group.name, iconName: group.icon, tone: group.tone,
                                 subcategoryCount: group.subs.count))
            for (position, sub) in group.subs.enumerated() {
                let subID = nextID()
                entries.append(.init(id: subID, name: sub.name, iconName: sub.icon, tone: group.tone,
                                     parentID: groupID, siblingPosition: position))
                records += sub.amounts.map {
                    ExpenseRecord(amountMinor: $0, date: now, categoryID: subID, groupID: groupID)
                }
            }
            records += group.direct.map { ExpenseRecord(amountMinor: $0, date: now, categoryID: groupID) }
        }
        records += uncategorized.map { ExpenseRecord(amountMinor: $0, date: now, categoryID: nil) }
        let catalog = CategoryCatalogSnapshot(entries)
        let period = StatsPeriod.current(.month, now: now, calendar: calendar)
        let breakdown = StatisticsEngine(calendar: calendar)
            .groupBreakdown(for: period, records: records, stepRank: catalog.stepRank)
        return CategoryVizData(breakdown: breakdown, catalog: catalog)
    }
}
#endif
