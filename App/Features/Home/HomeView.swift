import SwiftData
import SwiftUI
import ExpenseCore

/// Вкладка «Траты» (макеты `01-home`, `02-home-ring`, `03-home-range`): шапка периода и сегмент, под ними —
/// один `List(.plain)`: бумажный лист (r 28 сверху) с итогом, фразой-сравнением и обзором категорий, дальше
/// лента выбранного периода по дням с липкими стеклянными заголовками. В виде «Кольцо» кольцо стоит на ауре,
/// лист начинается под ним. Вид обзора — настройка `SettingsKeys.homeOverviewStyle`.
///
/// Шапка — над `List` в `VStack`: закреплённые заголовки секций игнорируют верхние safe area (AGENTS.md).
/// Лист — фон строк и подложка за `List` от верха листа до низа экрана (`HomeSheetUnderlay`).
/// Свайпы строк работают только в `List`: вправо — «Повторить» (копия на сейчас), влево — «Удалить» с тостом.
struct HomeView: View {
    @Query(sort: [
        SortDescriptor(\Expense.date, order: .reverse),
        SortDescriptor(\Expense.createdAt, order: .reverse)
    ])
    private var expenses: [Expense]
    @Query private var categories: [ExpenseCategory]

    @AppStorage(SettingsKeys.homeOverviewStyle) private var storedOverviewStyle = HomeOverviewStyle.default
    @Environment(AppRouter.self) private var router
    @Environment(PendingDeletion.self) private var pendingDeletion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var money
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var period = HomeView.initialPeriod()
    @State private var sheetTop = HomeSheetTop()
    /// Строка только что сохранённой траты: подсветка tint 12 % гаснет (save-reward).
    @State private var highlightedID: UUID?
    @State private var selectionCount = 0
    @State private var repeatCount = 0
    @State private var errorMessage: String?

    var body: some View {
        let visible = expenses.filter { !pendingDeletion.hiddenIDs.contains($0.id) }
        let content = HomeContent(
            expenses: visible,
            categories: categories,
            period: period.period,
            now: period.now,
            calendar: period.calendar
        )
        let texts = HomeTexts(money: money, calendar: period.calendar, now: period.now)

        VStack(spacing: Theme.Spacing.xs) {
            VStack(spacing: Theme.Spacing.md) {
                PeriodHeader(selection: period, style: .home, auraTones: content.auraTones)
                PeriodSegment(selection: period)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            feed(content, texts: texts)
        }
        .padding(.top, Theme.Spacing.sm)
        .background { AuraBackground(tones: content.auraTones).ignoresSafeArea() }
        .sensoryFeedback(Haptic.selection, trigger: selectionCount)
        .sensoryFeedback(Haptic.success, trigger: repeatCount)
        .errorAlert($errorMessage)
    }

    // MARK: - Лента

    private func feed(_ content: HomeContent, texts: HomeTexts) -> some View {
        ScrollViewReader { proxy in
            List {
                overview(content, texts: texts)
                ForEach(content.days) { day in
                    Section {
                        ForEach(day.rows) { row in
                            feedRow(row)
                        }
                        daySpacer
                    } header: {
                        FeedDayHeader(
                            title: texts.dayTitle(day.day),
                            totalMinor: day.totalMinor,
                            accessibilityText: texts.dayAccessibility(day.day, totalMinor: day.totalMinor)
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
            .motion(Motion.enter, value: content.rowIDs)
            // Другой период — новый список с начала, без анимации всех строк сразу.
            .id(period.period)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { sheetTop.listTop = $0 }
            .background(alignment: .top) { HomeSheetUnderlay(sheetTop: sheetTop) }
            .onChange(of: router.savedExpenseID) { _, id in
                showSaved(id, proxy: proxy)
            }
            .task(id: highlightedID) { await fadeHighlight() }
            #if DEBUG
            .task { await HomeDebug.scrollIfRequested(content, proxy: proxy) }
            #endif
        }
    }

    /// Начало листа и всё, что над лентой: итог и обзор, пустые состояния.
    @ViewBuilder
    private func overview(_ content: HomeContent, texts: HomeTexts) -> some View {
        // Зазор сегмент → лист 16 (с отступом стека): в нём видна тень листа.
        Color.clear
            .frame(height: Theme.Spacing.md)
            .homeRow(background: Color.clear)
            .accessibilityHidden(true)

        switch content.state {
        case .firstRun:
            HomeFirstRun()
                .padding(.vertical, Theme.Spacing.xl)
                .sheetTopRow(sheetTop)
        case .emptyPeriod(let latest):
            HomeEmptyPeriod(message: texts.emptyPeriod(period.period, isCurrent: period.isCurrent)) {
                showLatestExpense(latest)
            }
            .padding(.vertical, Theme.Spacing.xl)
            .sheetTopRow(sheetTop)
        case .filled:
            let comparison = texts.comparison(content.summary, period: period.period)
            let periodName = texts.periodName(period.period)
            switch overviewStyle {
            case .tiles:
                HomeTilesSummary(
                    content: content,
                    comparison: comparison,
                    texts: texts,
                    periodName: periodName,
                    onSelect: openStatistics
                )
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.lg)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(verbatim: L10n.format("home.summary.a11y", periodName)))
                .sheetTopRow(sheetTop)
            case .ring:
                HomeRingSummary(content: content, comparison: comparison, periodName: periodName, onSelect: openStatistics)
                    .homeRow(background: Color.clear)
                // Верх листа под кольцом: до заголовка первого дня 16 (12 + поле заголовка 4).
                Color.clear
                    .frame(height: Theme.Spacing.md)
                    .accessibilityHidden(true)
                    .sheetTopRow(sheetTop)
            }
        }
    }

    /// Строка траты: тап — правка; свайпы и действия VoiceOver «Удалить», «Повторить сегодня» (`feed.row.a11y`).
    private func feedRow(_ row: ExpenseRowData) -> some View {
        Button {
            router.presentEdit(expenseID: row.id)
        } label: {
            ExpenseRow(data: row)
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                repeatExpense(row.id)
            } label: {
                Label("feed.swipe.repeat", systemImage: "arrow.clockwise")
            }
            .tint(Theme.graphic)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(row.id)
            } label: {
                Label("feed.swipe.delete", systemImage: "trash")
            }
        }
        .accessibilityAction(named: Text("feed.row.a11y.delete")) { delete(row.id) }
        .accessibilityAction(named: Text("feed.row.a11y.repeat")) { repeatExpense(row.id) }
        .id(row.id)
        .homeRow(background: rowBackground(row))
    }

    /// Лист под строкой; у только что сохранённой — подсветка tint категории 12 %.
    private func rowBackground(_ row: ExpenseRowData) -> some View {
        Theme.surface.overlay {
            CategoryPaint.main(row.tone)
                .opacity(highlightedID == row.id ? Motion.saveHighlightOpacity : 0)
        }
    }

    /// Зазор между днями: 16 до следующего заголовка (12 + его поле 4).
    private var daySpacer: some View {
        Color.clear
            .frame(height: Theme.Spacing.md)
            .accessibilityHidden(true)
            .homeRow(background: Theme.surface)
    }

    // MARK: - Вид обзора

    private var overviewStyle: HomeOverviewStyle {
        #if DEBUG
        HomeDebug.overviewStyle ?? storedOverviewStyle
        #else
        storedOverviewStyle
        #endif
    }

    // MARK: - Действия

    /// Плитка или сегмент → статистика с тем же периодом и раскрытой категорией (§4.9).
    private func openStatistics(_ item: CategoryVizItemID) {
        let groupID: UUID? = if case .category(let id) = item { id } else { nil }
        router.openStatistics(period: period.period, groupID: groupID)
    }

    /// «К последней трате»: период того же вида с последней тратой; свой — диапазон той же длины, кончающийся ею.
    private func showLatestExpense(_ latest: Date) {
        let calendar = period.calendar
        if let kind = period.period.kind {
            period.apply(.current(kind, now: latest, calendar: calendar))
        } else {
            let last = calendar.startOfDay(for: latest)
            let first = calendar.date(byAdding: .day, value: -(period.dayCount - 1), to: last) ?? last
            period.applyCustom(from: first, through: last)
        }
        selectionCount += 1
    }

    private func delete(_ id: UUID) {
        let item = PendingDeletion.Item(id: id, title: String(localized: "toast.deleted.title"))
        pendingDeletion.schedule(item, store: ExpenseStore(context: modelContext))
    }

    /// «Повторить»: такая же трата (сумма, категория, заметка) с датой «сейчас».
    private func repeatExpense(_ id: UUID) {
        let store = ExpenseStore(context: modelContext)
        do {
            guard let expense = try store.expense(id: id) else { return }
            try store.addExpense(
                amountMinor: expense.amountMinor,
                date: .now,
                note: expense.note,
                category: expense.category
            )
            repeatCount += 1
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    // MARK: - save-reward

    /// «Сохранить» в шите: строка влетает (анимация ленты `enter`), прокрутка к ней и подсветка.
    private func showSaved(_ id: UUID?, proxy: ScrollViewProxy) {
        guard let id else { return }
        router.savedExpenseID = nil
        guard router.tab == .expenses else { return }
        highlightedID = id
        withAnimation(Motion.animation(Motion.enter, reduceMotion: reduceMotion)) {
            proxy.scrollTo(id)
        }
    }

    /// Подсветка держится, пока закрывается шит, и гаснет за 0,8 с.
    private func fadeHighlight() async {
        guard let id = highlightedID else { return }
        try? await Task.sleep(for: HomeMetrics.highlightHold)
        guard !Task.isCancelled, highlightedID == id else { return }
        withAnimation(Motion.animation(Motion.saveHighlightFade, reduceMotion: reduceMotion)) {
            highlightedID = nil
        }
    }

    // MARK: - Запуск

    private static func initialPeriod() -> PeriodSelection {
        #if DEBUG
        HomeDebug.initialPeriod() ?? PeriodSelection()
        #else
        PeriodSelection()
        #endif
    }
}

/// Размеры и тайминги главной, которых нет в токенах.
nonisolated enum HomeMetrics {
    /// Подсветка новой строки держится, пока шит записи уезжает (≈ длина его ухода), потом гаснет.
    static let highlightHold: Duration = .milliseconds(450)
}

// MARK: - Лист

/// Верх листа и `List` в координатах экрана. Пишет строка-начало листа при прокрутке, читает только подложка:
/// экран целиком при этом не пересчитывается.
@Observable
final class HomeSheetTop {
    var listTop: CGFloat = 0
    var sheetTop: CGFloat?
}

/// Бумажный лист за `List` от верха листа до низа экрана: виден, когда строк мало и при оттягивании.
private struct HomeSheetUnderlay: View {
    let sheetTop: HomeSheetTop

    var body: some View {
        if let top = sheetTop.sheetTop {
            PaperSheetBackground()
                .padding(.top, top - sheetTop.listTop)
                .clipped()
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private extension View {
    /// Строка `List` главной: поля экрана 16, без разделителя, свой фон.
    func homeRow(background: some View) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.screen, bottom: 0, trailing: Theme.Spacing.screen))
            .listRowSeparator(.hidden)
            .listRowBackground(background)
    }

    /// Первая строка листа: скруглённый верх r 28 и замер его положения для подложки.
    func sheetTopRow(_ sheetTop: HomeSheetTop) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { sheetTop.sheetTop = $0 }
            .homeRow(background: PaperSheetBackground.shape.fill(Theme.surface))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(AppRouter())
    .environment(PendingDeletion())
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
#endif
