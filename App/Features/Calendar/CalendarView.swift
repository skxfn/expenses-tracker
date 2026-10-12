import SwiftData
import SwiftUI
import ExpenseCore

/// Вкладка «Календарь» (макет 09): шапка месяца с ‹ ›, строка-итог, сетка heat с линзой выбранного дня,
/// шкала и бумажный лист выбранного дня со строками трат и «Записать на …».
/// Всё под шапкой — один `List`: свайпы строк работают только в нём (ловушка AGENTS.md).
/// Траты выбирает `CalendarModel` (год месяца и выбранный день), а не `@Query` всех трат: перевод
/// в `ExpenseRecord` в `body` на каждом касании стоил ≈ 6 мкс на трату.
struct CalendarView: View {
    @Query private var categories: [ExpenseCategory]

    @Environment(AppRouter.self) private var router
    @Environment(PendingDeletion.self) private var pendingDeletion
    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var money
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = CalendarModel()
    /// Верх `List` и верх листа дня в глобальных координатах: лист тянется фоном до низа экрана.
    @State private var listTop: CGFloat = 0
    @State private var sheetTop: CGFloat?
    @State private var selectionTick = 0
    @State private var repeatTick = 0
    @State private var longPressTick = 0
    @State private var errorMessage: String?

    var body: some View {
        let strings = CalendarStrings(money: money, calendar: model.calendar, now: model.now)

        VStack(spacing: Theme.Spacing.md) {
            header(strings)
                .padding(.horizontal, Theme.Spacing.screen)
            list(strings, dayRows: model.dayRows)
        }
        .padding(.top, Theme.Spacing.sm)
        .background { AuraBackground(tones: auraTones).ignoresSafeArea() }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sensoryFeedback(Haptic.selection, trigger: selectionTick)
        .sensoryFeedback(Haptic.success, trigger: repeatTick)
        .sensoryFeedback(Haptic.medium, trigger: longPressTick)
        .onAppear {
            model.appear(ExpenseStore(context: modelContext), hiddenIDs: pendingDeletion.hiddenIDs)
        }
        .onDisappear { model.disappear() }
        .onDataSaved { model.dataDidChange() }
        .onChange(of: pendingDeletion.hiddenIDs) { _, ids in
            model.setHiddenIDs(ids)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
        .onCalendarDayChange { model.refresh() }
        .errorAlert($errorMessage)
    }

    // MARK: Шапка

    private func header(_ strings: CalendarStrings) -> some View {
        let month = model.month
        let title = strings.monthTitle(month)
        return CalendarHeader(
            month: title.name,
            year: title.year,
            titleAccessibility: strings.headerAccessibility(month),
            previousAccessibility: strings.stepAccessibility(from: month, to: month.previous(), key: "header.prev.a11y"),
            nextAccessibility: strings.stepAccessibility(from: month, to: month.next(), key: "header.next.a11y"),
            canGoNext: model.canShowNext,
            onPrevious: { step(forward: false) },
            onNext: { step(forward: true) }
        )
    }

    // MARK: Сетка и лист дня

    private func list(_ strings: CalendarStrings, dayRows: [ExpenseRowData]) -> some View {
        List {
            CalendarSummaryLine(
                summary: strings.summary(model.summary, month: model.month, isCurrent: model.isCurrentMonth),
                accessibilityText: strings.summaryAccessibility(model.summary, month: model.month, isCurrent: model.isCurrentMonth)
            )
            .padding(.bottom, Theme.Spacing.lg)
            .calendarRow()

            if model.latestExpenseOutsideEmptyMonth != nil {
                Button("home.empty.period.action") { showLatestExpense() }
                    .buttonStyle(.glassCapsule(.glass, height: Theme.Size.chip, expands: false))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Theme.Spacing.lg)
                    .calendarRow()
            }

            CalendarGrid(
                model: model,
                strings: strings,
                onSelect: select,
                onAdd: addByLongPress,
                onSwipe: step(forward:)
            )
            .padding(.bottom, Theme.Spacing.md)
            .calendarRow()

            if let scale = model.heatScale {
                HeatLegend(
                    title: strings.legendTitle,
                    items: strings.legendItems(scale),
                    accessibilityText: strings.legendAccessibility(scale)
                )
                .padding(.bottom, Theme.Spacing.lg)
                .calendarRow()
            }

            dayTitle(strings)
                .padding(.top, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.sm)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { sheetTop = $0 }
                .calendarRow(background: PaperSheetBackground.shape.fill(Theme.surface))

            if dayRows.isEmpty {
                Text("cal.emptyDay")
                    .typeStyle(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.chip, alignment: .leading)
                    .calendarRow(background: Theme.surface)
            }
            ForEach(dayRows) { row in
                expenseRow(row)
                    .calendarRow(background: Theme.surface)
            }

            addButton(strings)
                .padding(.top, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
                .calendarRow(background: Theme.surface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { listTop = $0 }
        .background(alignment: .top) { sheetBackground }
    }

    /// «Четверг, 8 октября» (Title) + сумма дня (Unbounded 22). При переполнении — «Чт, 8 октября»,
    /// на крупном тексте — сумма под датой (дата в строку, иначе «Чт, 8 октября», и лишь затем перенос).
    private func dayTitle(_ strings: CalendarStrings) -> some View {
        let day = model.selected
        let full = Text(verbatim: strings.dayTitle(day.date))
        let short = Text(verbatim: strings.dayTitle(day.date, shortWeekday: true))
        let spoken = day.totalMinor > 0 ? ", " + strings.spoken(day.totalMinor) : ""
        return ViewThatFits(in: .horizontal) {
            dayTitleRow(full, total: day.totalMinor)
            dayTitleRow(short, total: day.totalMinor)
            dayTitleStack(full.lineLimit(1), total: day.totalMinor)
            dayTitleStack(short.lineLimit(1), total: day.totalMinor)
            dayTitleStack(short.lineLimit(nil), total: day.totalMinor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: strings.sheetAccessibility(day.date) + spoken))
        .accessibilityAddTraits(.isHeader)
    }

    private func dayTitleRow(_ title: Text, total: Int64) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            title
                .typeStyle(.title)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: Theme.Spacing.sm)
            dayAmount(total)
                .fixedSize()
        }
    }

    /// Дата строкой, сумма под ней.
    private func dayTitleStack(_ title: some View, total: Int64) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            title
            dayAmount(total)
        }
        .typeStyle(.title)
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func dayAmount(_ total: Int64) -> some View {
        if total > 0 {
            Text(verbatim: money.string(fromMinor: total, style: .plain))
                .typeStyle(.calendarDayAmount)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(total)))
                .motion(Motion.number, value: total)
        }
    }

    /// Строка траты: тап — правка; свайп вправо — «Повторить» (копия на сейчас), влево — «Удалить» с тостом.
    private func expenseRow(_ data: ExpenseRowData) -> some View {
        Button {
            router.presentEdit(expenseID: data.id)
        } label: {
            ExpenseRow(data: data)
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                repeatExpense(data.id)
            } label: {
                Label("feed.swipe.repeat", systemImage: "arrow.clockwise")
            }
            .tint(Theme.graphic)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(data.id)
            } label: {
                Label("feed.swipe.delete", systemImage: "trash")
            }
        }
        .accessibilityAction(named: Text("feed.row.a11y.delete")) { delete(data.id) }
        .accessibilityAction(named: Text("feed.row.a11y.repeat")) { repeatExpense(data.id) }
    }

    /// Стеклянная «+ Записать на 8 окт» (`glass-in`). Выбранный день всегда не будущий —
    /// будущие дни без трат не выбираются, поэтому кнопка есть всегда.
    private func addButton(_ strings: CalendarStrings) -> some View {
        let date = model.selectedDay
        return Button {
            router.presentAdd(date: model.entryDateForSelectedDay)
        } label: {
            Label(strings.addForDay(date), systemImage: "plus")
                .minimumScaleFactor(0.5)
        }
        .buttonStyle(.glassCapsule(.glass, height: Theme.Size.chip, expands: false))
        .accessibilityLabel(Text(verbatim: strings.addForDayAccessibility(date)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Лист дня фоном `List` от его верха до низа экрана — и когда трат мало, и при оттягивании.
    @ViewBuilder
    private var sheetBackground: some View {
        if let sheetTop {
            PaperSheetBackground()
                .padding(.top, sheetTop - listTop)
                .clipped()
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Аура

    /// Тоны крупнейших категорий месяца (tint; в тёмной — darktint).
    private var auraTones: [GouacheTone] {
        var tones: [UUID: GouacheTone] = [:]
        for category in categories where category.parent == nil {
            tones[category.id] = GouacheTone(mainHex: category.colorHex)
        }
        return model.topGroupIDs.compactMap { tones[$0] }
    }

    // MARK: Действия

    private func select(_ date: Date) {
        guard date != model.selectedDay else { return }
        model.select(date)
        selectionTick += 1
    }

    /// Долгое нажатие на клетку (`cal.longPress.a11y`): выбрать день и записать трату на него.
    private func addByLongPress(_ date: Date) {
        model.select(date)
        longPressTick += 1
        router.presentAdd(date: model.entryDateForSelectedDay)
    }

    /// «К последней трате» в пустом месяце.
    private func showLatestExpense() {
        withAnimation(Motion.animation(Motion.select, reduceMotion: reduceMotion)) {
            model.showLatestExpense()
        }
        selectionTick += 1
    }

    private func step(forward: Bool) {
        guard !forward || model.canShowNext else { return }
        withAnimation(Motion.animation(Motion.select, reduceMotion: reduceMotion)) {
            if forward { model.showNext() } else { model.showPrevious() }
        }
        selectionTick += 1
    }

    private func delete(_ id: UUID) {
        let item = PendingDeletion.Item(id: id, title: String(localized: "toast.deleted.title"))
        pendingDeletion.schedule(item, store: ExpenseStore(context: modelContext))
    }

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
            repeatTick += 1
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

private extension View {
    /// Строка `List` календаря на ауре: поля экрана 16, без разделителя, фон прозрачный.
    func calendarRow() -> some View {
        calendarRow(background: Color.clear)
    }

    /// Строка листа дня: фон — бумага листа.
    func calendarRow(background: some View) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.screen, bottom: 0, trailing: Theme.Spacing.screen))
            .listRowSeparator(.hidden)
            .listRowBackground(background)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CalendarView()
    }
    .environment(AppRouter(tab: .calendar))
    .environment(PendingDeletion())
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
#endif
