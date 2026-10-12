import SwiftData
import SwiftUI
import ExpenseCore

/// Вкладка «Статистика» (макеты `04-stats*`, `05-stats-range`; INTEGRATION §2.1, §2.2, §4.6–4.8, §6).
///
/// Сверху на ауре — Large Title, шапка периода, сегмент и сводка; ниже бумажный лист с блоками:
/// «Категории» (4 вида с раскрытием), «По дням» (у «Дня» — «По часам», у «Года» — по месяцам), «Темп»,
/// «Привычки», «2026 по дням», «Крупнейшие траты». Раскрытая категория фильтрует сводку и все блоки под
/// «Категориями» (пометка «только Продукты»). Тап по плитке на главной приходит `AppRouter.statisticsFocus`:
/// период применяется сразу, категория раскрывается с анимацией.
/// Траты читает и держит `StatisticsModel` (при появлении и после сохранений базы), не `@Query` в `body`.
struct StatisticsView: View {
    @Query private var categories: [ExpenseCategory]
    @AppStorage(SettingsKeys.statsCategoryView) private var categoryView: StatsCategoryView = .default

    @State private var selection: PeriodSelection
    @State private var model = StatisticsModel()
    @State private var expandedID: UUID?
    /// Категория из `statisticsFocus`: раскрывается после перехода, чтобы было видно анимацию.
    @State private var pendingExpansion: UUID?

    @Environment(AppRouter.self) private var router
    @Environment(PendingDeletion.self) private var pendingDeletion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var money

    init() {
        let selection = PeriodSelection()
        #if DEBUG
        StatsDebugOptions.applyPeriod(to: selection)
        #endif
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let input = StatisticsInput(
            catalog: CategoryCatalogSnapshot(categories: categories),
            period: selection.period,
            now: selection.now,
            expandedID: expandedID,
            hiddenIDs: pendingDeletion.hiddenIDs
        )
        let texts = StatsTexts(money: money, calendar: selection.calendar, now: selection.now)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(texts)
                        .padding(.horizontal, Theme.Spacing.screen)
                        .id(StatsAnchor.summary)
                    sheet(texts)
                        .padding(.top, Theme.Spacing.md)
                }
            }
            .onChange(of: router.statisticsFocus, initial: true) { _, focus in
                applyFocus(focus, proxy: proxy)
            }
            #if DEBUG
            .task { await StatsDebugOptions.scroll(proxy) }
            #endif
        }
        .background { AuraBackground(tones: model.auraTones).ignoresSafeArea() }
        .onChange(of: input, initial: true) { _, input in
            model.update(input)
        }
        .onAppear { model.appear(in: modelContext) }
        .onDisappear { model.disappear() }
        .onDataSaved { model.dataDidChange(in: modelContext) }
        .task(id: pendingExpansion) {
            guard let id = pendingExpansion else { return }
            try? await Task.sleep(for: StatsLayout.focusExpansionDelay)
            expandedID = id
            pendingExpansion = nil
        }
        #if DEBUG
        .onChange(of: model.categories) { _, data in
            if expandedID == nil, let id = StatsDebugOptions.expansion(in: data) {
                expandedID = id
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            if let id = StatsDebugOptions.focusGroup(in: model.input.catalog) {
                router.openStatistics(period: selection.period.previous(in: selection.calendar), groupID: id)
            }
        }
        #endif
    }

    // MARK: - Шапка и сводка

    private func header(_ texts: StatsTexts) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                PeriodHeader(selection: selection, style: .statistics, auraTones: model.auraTones)
                PeriodSegment(selection: selection)
            }
            if model.hasExpenses, !model.isPeriodEmpty {
                StatsSummaryView(
                    lead: texts.lead(model.period, summary: model.summary),
                    summary: model.summary,
                    comparison: texts.shared.comparison(model.summary, period: model.period),
                    meta: texts.meta(model.summary),
                    spokenMeta: texts.spokenMeta(model.summary),
                    filterMark: filterMark(texts),
                    spokenTotal: texts.shared.spoken(model.summary.totalMinor)
                )
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Лист

    /// Бумажный лист; фон уходит за нижний край и под таб-бар (`ignoresSafeArea` в прокрутке не дотягивается).
    private func sheet(_ texts: StatsTexts) -> some View {
        VStack(alignment: .leading, spacing: StatsLayout.sectionSpacing) {
            if !model.hasExpenses {
                emptyNone
            } else if model.isPeriodEmpty {
                emptyPeriod(texts)
            } else {
                sections(texts)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, StatsLayout.sectionSpacing)
        .background(alignment: .top) {
            PaperSheetBackground()
                .padding(.bottom, -StatsLayout.sheetOverscroll)
        }
    }

    @ViewBuilder
    private func sections(_ texts: StatsTexts) -> some View {
        let mark = filterMark(texts)

        StatsCategorySection(
            data: model.categories,
            view: $categoryView,
            expandedID: $expandedID,
            periodName: texts.periodName(model.period)
        )
        .id(StatsAnchor.categories)

        if let series = model.series {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                StatsSectionHeader(title: seriesTitle(series.step), filterMark: mark)
                StatsBarsChart(
                    series: series,
                    period: model.period,
                    now: model.now,
                    averageMinor: series.step == .day ? model.summary.averagePerDayMinor : nil,
                    texts: texts
                )
            }
            .id(StatsAnchor.days)
        }

        if let pace = model.pace {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                StatsSectionHeader(title: Text("stats.pace.heading"), filterMark: mark)
                StatsPaceView(pace: pace, period: model.period, texts: texts)
            }
            .id(StatsAnchor.pace)
        }

        if let habits = model.habits {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                StatsSectionHeader(
                    title: Text("stats.habits.heading"),
                    filterMark: mark,
                    note: habits.hasEnoughData ? L10n.format("stats.habits.note", money.currencySymbol) : nil
                )
                StatsHabitsView(state: habits, texts: texts)
            }
            .id(StatsAnchor.habits)
        }

        if let year = model.year {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                StatsSectionHeader(title: Text(verbatim: L10n.format("stats.year.heading", String(year.year))), filterMark: mark)
                StatsYearHeatmap(
                    state: year,
                    now: model.now,
                    texts: texts,
                    legend: CalendarStrings(money: money, calendar: model.calendar, now: model.now)
                )
            }
            .id(StatsAnchor.year)
        }

        let top = model.topRows
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                StatsSectionHeader(title: Text("stats.top.heading"), filterMark: mark)
                StatsTopSection(rows: top) { router.presentEdit(expenseID: $0) }
            }
            .id(StatsAnchor.top)
        }
    }

    private func seriesTitle(_ step: StatsTimeStep) -> Text {
        switch step {
        case .hour: Text("stats.dayView.heading")
        case .month: Text("stats.months.heading")
        case .day, .week: Text("stats.days.heading")
        }
    }

    private func filterMark(_ texts: StatsTexts) -> String? {
        model.filterGroup.map(texts.filterMark)
    }

    // MARK: - Пустые состояния

    /// Трат нет совсем (`stats.empty.none`): Headline + строка SF 15 secondary.
    private var emptyNone: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("stats.empty.none.title")
                .typeStyle(.headline)
                .foregroundStyle(Theme.ink)
            Text("stats.empty.none.body")
                .typeStyle(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
    }

    /// Период без трат: «В сентябре трат не было» / «… пока нет трат» и стеклянная «К последней трате».
    private func emptyPeriod(_ texts: StatsTexts) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(verbatim: texts.shared.emptyPeriod(model.period))
                .typeStyle(.headline)
                .foregroundStyle(Theme.ink)
            if model.lastExpenseDate != nil {
                Button("home.empty.period.action", action: showLastExpense)
                    .buttonStyle(.glassCapsule(.glass, height: Theme.Size.chip, expands: false))
            }
        }
    }

    // MARK: - Действия

    /// Период того же вида с последней тратой; свой — той же длины, кончающийся днём последней траты.
    private func showLastExpense() {
        guard let date = model.lastExpenseDate else { return }
        if let kind = selection.period.kind {
            selection.apply(.current(kind, now: date, calendar: selection.calendar))
        } else {
            let first = selection.calendar.date(byAdding: .day, value: -(selection.dayCount - 1), to: date) ?? date
            selection.applyCustom(from: first, through: date)
        }
    }

    /// Задание из главной: тот же период и раскрытая категория.
    private func applyFocus(_ focus: StatisticsFocus?, proxy: ScrollViewProxy) {
        guard let focus else { return }
        router.statisticsFocus = nil
        selection.apply(focus.period)
        expandedID = nil
        proxy.scrollTo(StatsAnchor.summary, anchor: .top)
        pendingExpansion = focus.groupID
    }
}

/// Якоря прокрутки блоков (`-statsScroll` и переход из главной).
enum StatsAnchor: String {
    case summary, categories, days, pace, habits, year, top
}
