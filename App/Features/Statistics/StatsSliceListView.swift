import SwiftData
import SwiftUI
import ExpenseCore

/// Траты среза статистики (пуш из журнала категории, столбика, «Темпа», «Привычек», карты года): Large Title —
/// что за срез («Кафе», «Четверг, 8 октября», «По пятницам»), под ним период или пометка «только Кафе», итог
/// и число трат; дальше лента по дням, как на вкладке «Траты»: липкие стеклянные заголовки дней, строки
/// `ExpenseRow`, тап — правка, свайпы «Повторить» / «Удалить». Траты читает `StatsSliceListModel`.
struct StatsSliceListView: View {
    @State private var model: StatsSliceListModel
    @State private var errorMessage: String?

    @Environment(PendingDeletion.self) private var pendingDeletion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var money
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(route: StatsSliceRoute) {
        _model = State(initialValue: StatsSliceListModel(route: route))
    }

    var body: some View {
        let texts = StatsSliceTexts(model: model, money: money)
        let feed = HomeTexts(money: money, calendar: model.calendar, now: .now)

        List {
            header(texts)
                .listRowInsets(EdgeInsets(top: Theme.Spacing.sm, leading: Theme.Spacing.screen,
                                          bottom: Theme.Spacing.xl, trailing: Theme.Spacing.screen))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            if model.isLoaded, model.days.isEmpty {
                Text("stats.slice.empty")
                    .typeStyle(.headline)
                    .foregroundStyle(Theme.ink)
                    .sliceRow()
            }
            ForEach(model.days) { day in
                Section {
                    ForEach(day.rows) { row in
                        ExpenseFeedRow(data: row) { errorMessage = $0 }
                            .sliceRow()
                    }
                    Color.clear
                        .frame(height: Theme.Spacing.md)
                        .accessibilityHidden(true)
                        .sliceRow()
                } header: {
                    FeedDayHeader(
                        title: feed.dayTitle(day.day),
                        totalMinor: day.totalMinor,
                        accessibilityText: feed.dayAccessibility(day.day, totalMinor: day.totalMinor)
                    )
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.surface)
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(0)
        .environment(\.defaultMinListRowHeight, 0)
        .animation(reduceMotion ? nil : Motion.enter, value: model.days.flatMap { $0.rows.map(\.id) })
        .background {
            AuraBackground(tones: model.tone.map { [$0] } ?? [], base: Theme.surface, layout: Self.auraLayout)
                .ignoresSafeArea()
        }
        .navigationTitle(Text(verbatim: texts.title))
        .navigationBarTitleDisplayMode(.large)
        .errorAlert($errorMessage)
        .onAppear { model.reload(context: modelContext, hiddenIDs: pendingDeletion.hiddenIDs) }
        .onDataSaved { model.reload(context: modelContext, hiddenIDs: pendingDeletion.hiddenIDs) }
        .onChange(of: pendingDeletion.hiddenIDs) { _, hidden in model.update(hiddenIDs: hidden) }
    }

    /// Период или пометка «только Кафе», итог Unbounded 28 и «9 трат».
    private func header(_ texts: StatsSliceTexts) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let subtitle = texts.subtitle {
                Text(verbatim: subtitle)
                    .typeStyle(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            AmountText(
                text: money.string(fromMinor: model.totalMinor, style: .plain),
                value: Double(model.totalMinor),
                size: .ringTotal,
                currency: money.currencySymbol,
                accessibilityText: texts.stats.shared.spoken(model.totalMinor)
            )
            Text(verbatim: L10n.format("stats.slice.count", model.count))
                .typeStyle(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Аура тона категории только за шапкой: строки ленты лежат на бумаге.
    private static let auraLayout = Array(AuraBackground.defaultLayout.prefix(2)).map {
        AuraBackground.Spot(center: $0.center, radius: CGSize(width: $0.radius.width, height: 0.3), opacity: $0.opacity)
    }
}

/// Заголовок и подпись среза: журнал категории — «Кафе» и «октябрь»; столбик дня — «Четверг, 8 октября»
/// и «только Кафе»; час — «14:00» и «8 октября»; месяц — «Октябрь»; день недели — «По пятницам» и «октябрь».
struct StatsSliceTexts {
    let model: StatsSliceListModel
    let stats: StatsTexts

    init(model: StatsSliceListModel, money: MoneyFormatter) {
        self.model = model
        stats = StatsTexts(money: money, calendar: model.calendar, now: .now)
    }

    private var dates: any DateTextFormatter { stats.dates }
    private var slice: StatsExpenseSlice { model.route.slice }
    private var start: Date { slice.interval.start }

    var title: String {
        switch slice.scope {
        case .period:
            return model.filterName ?? dates.capitalized(stats.periodName(model.route.period))
        case .bucket(.hour):
            return dates.hour(start)
        case .bucket(.month):
            return stats.monthTitle(start)
        case .bucket(.week):
            return dates.range(slice.interval)
        case .bucket(.day):
            return dates.full(start)
        case .weekday(let weekday):
            return stats.weekdayTitle(weekday)
        }
    }

    /// Период (журнал, день недели), день (час) и пометка категории через « · »; `nil` — подписи нет.
    var subtitle: String? {
        var parts: [String] = []
        switch slice.scope {
        case .period:
            if model.filterName != nil { parts.append(stats.periodName(model.route.period)) }
        case .bucket(.hour):
            parts.append(dates.dayMonth(start))
        case .weekday:
            parts.append(stats.periodName(model.route.period))
        case .bucket:
            break
        }
        if slice.scope != .period, let name = model.filterName {
            parts.append(L10n.format("viz.drill.filter", name))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private extension View {
    /// Строка списка: поля экрана 16, без разделителя, на бумаге.
    func sliceRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.screen, bottom: 0, trailing: Theme.Spacing.screen))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
