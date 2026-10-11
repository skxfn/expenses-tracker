import Combine
import SwiftData
import SwiftUI
import UIKit
import ExpenseCore

/// Шит «Новая трата» / «Трата» (макеты `06-add`, `08-add-edit`). Всё для ввода — в нижней половине:
/// сумма и категория → пилюля пакета → образцы → дата и заметка → [Ещё одна | Удалить] [Сохранить]
/// → быстрые суммы над системной цифровой клавиатурой. Аура — цветом выбранной категории над клавиатурой.
struct ExpenseEntryView: View {
    /// Шиты поверх шита записи.
    enum SubSheet: String, Identifiable {
        case picker, date, batch
        var id: Self { self }
    }

    private enum Field: Hashable {
        case amount, note
    }

    /// «Ещё одна»: сумма улетает вверх (design.json → motion `another-one`).
    private static let flyDistance: CGFloat = 24
    private static let flyBlur: CGFloat = 4
    /// Пятно ауры над клавиатурой (у нижнего края шита, в цвет выбранной категории).
    private static let auraLayout = [
        AuraBackground.Spot(center: UnitPoint(x: 0.5, y: 0.5), radius: CGSize(width: 0.9, height: 0.42), opacity: 0.9),
    ]

    @State private var model: ExpenseFormModel
    @State private var subSheet: SubSheet?
    @State private var isEditingNote = false
    @State private var isConfirmingDiscard = false
    @State private var isShowingSaveError = false
    @State private var isFlyingAway = false
    @State private var amountWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    /// Видимая высота прокрутки над рядом кнопок: пока всё помещается, раскладка занимает её целиком.
    @State private var visibleHeight: CGFloat = 0
    /// Высота раскладки над клавиатурой — держится, пока открыт шит поверх.
    @State private var keyboardLayoutHeight: CGFloat = 0
    /// Низ раскладки и верх панели быстрых сумм (в координатах окна) — для отступа под панель.
    @State private var keyboardLayoutBottom: CGFloat?
    @State private var quickBarTop: CGFloat?
    /// Шит поверх закрылся, клавиатура ещё не вернулась — раскладка держится.
    @State private var isWaitingForKeyboard = false
    // Триггеры тактильного отклика и тряски.
    @State private var selectionCount = 0
    /// Редактор новой категории поверх «Все категории» («+ Новая категория», «Создать «…»»).
    @State private var newCategory: CategoryEditorMode?
    @State private var quickCount = 0
    @State private var anotherCount = 0
    @State private var saveCount = 0
    @State private var shakeCount = 0
    @FocusState private var focus: Field?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var money
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(PendingDeletion.self) private var pendingDeletion
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: ExpenseFormModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            layout
                .sheetHeader(modeKey(add: "add.title", edit: "edit.title"), onClose: close)
                .toolbar { keyboardToolbar }
        }
        .presentationBackground {
            AuraBackground(tones: auraTones, edge: .bottom, base: Theme.canvasElevated, layout: Self.auraLayout)
                .animation(Motion.select, value: auraTones)
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.hasUnsavedChanges)
        .confirmationDialog(discardTitle, isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button(modeKey(add: "add.discard.discard", edit: "edit.discard.discard"), role: .destructive) {
                dismiss()
            }
            Button(modeKey(add: "add.discard.keep", edit: "edit.discard.keep"), role: .cancel) {
                focus = .amount
            }
        }
        .alert("add.save.error.title", isPresented: $isShowingSaveError) {
            Button("error.alert.ok", role: .cancel) {}
        } message: {
            Text("add.save.error.message")
        }
        .sheet(item: $subSheet, onDismiss: { focus = .amount }) { sheet in
            subSheetView(sheet)
        }
        .sensoryFeedback(Haptic.selection, trigger: selectionCount)
        .sensoryFeedback(Haptic.light, trigger: quickCount)
        .sensoryFeedback(Haptic.medium, trigger: anotherCount)
        .sensoryFeedback(Haptic.success, trigger: saveCount)
        .sensoryFeedback(Haptic.error, trigger: shakeCount)
        .onChange(of: focus) { _, newFocus in
            if newFocus != .note { isEditingNote = false }
        }
        .onChange(of: subSheet) { _, sheet in
            // Клавиатура шита записи не должна оставаться поверх шита «Все категории» и других;
            // после закрытия раскладка ждёт её возвращения (`onDismiss` → фокус на сумму).
            if sheet != nil {
                focus = nil
            } else {
                isWaitingForKeyboard = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            isWaitingForKeyboard = false
        }
        .onChange(of: pendingDeletion.item?.id) {
            model.pruneBatch(using: store)
        }
        .task {
            guard !model.isMissing else { return dismiss() }
            focus = .amount
            #if DEBUG
            await applyDebugRequest()
            #endif
        }
    }

    // MARK: - Раскладка

    /// Содержимое прокручивается над рядом кнопок: на размере по умолчанию всё помещается и не двигается,
    /// на крупном тексте «Сохранить» остаётся над клавиатурой (у `.decimalPad` нет клавиши «скрыть»).
    private var layout: some View {
        ScrollView {
            // Пока всё помещается — во всю видимую высоту, промежутки раздвигаются, как без прокрутки.
            FillHeightLayout(minHeight: visibleHeight) {
                content
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Размер без безопасных областей: между шапкой и рядом кнопок.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            actions
                .padding(.top, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.md)
                .padding(.bottom, focus == .amount || isLayoutFrozen ? quickBarInset : 0)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if focus == .amount, !isLayoutFrozen {
                keyboardLayoutHeight = frame.height
                keyboardLayoutBottom = frame.maxY
            }
        }
        // Под шитом поверх клавиатура прячется; раскладка остаётся как с клавиатурой (сумма видна над шитом, `07-picker`).
        .frame(height: isLayoutFrozen ? keyboardLayoutHeight : nil, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.keyboard, edges: isLayoutFrozen ? .bottom : [])
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Theme.Spacing.md)
            VStack(spacing: Theme.Spacing.xs) {
                amountField
                Text(verbatim: model.category?.line ?? String(localized: "add.categoryLine.none"))
                    .typeStyle(.callout)
                    .foregroundStyle(Theme.secondary)
                    // На крупном тексте «Продукты · Супермаркет» переносится, а не обрезается.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .multilineTextAlignment(.center)
            }
            .errorShake(trigger: shakeCount)
            if !visibleBatch.isEmpty {
                batchPill
                    .padding(.top, Theme.Spacing.md)
                    .transition(Motion.transition(.scale(scale: 0.9).combined(with: .opacity), reduceMotion: reduceMotion))
            }
            Spacer(minLength: Theme.Spacing.lg)
            EntrySwatchRow(
                swatches: model.swatches,
                selectedID: model.category?.id,
                onSelect: { choice in
                    model.toggle(choice)
                    selectionCount += 1
                },
                onShowAll: { subSheet = .picker }
            )
            dateAndNote
                .padding(.top, Theme.Spacing.md)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .frame(maxWidth: .infinity)
    }

    private var isLayoutFrozen: Bool {
        keyboardLayoutHeight > 0 && (subSheet != nil || isWaitingForKeyboard)
    }

    /// Место под панель быстрых сумм. Панель без общего фона то входит в безопасную область клавиатуры, то нет
    /// (iOS 26.5: при появлении шита — нет, после первой перерисовки — да), поэтому отступ — по факту:
    /// насколько раскладка заходит под панель. До замера — высота панели без зазора.
    private var quickBarInset: CGFloat {
        guard let keyboardLayoutBottom, let quickBarTop else { return Theme.Size.chip - Theme.Spacing.md }
        return max(keyboardLayoutBottom - quickBarTop, 0)
    }

    /// Сумма Unbounded 60 + символ валюты 26 в системном поле `.decimalPad`; не помещается — сжимается целиком.
    /// Растёт с текстом только до AX1: крупнее она занимает весь шит.
    private var amountField: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            TextField(text: amountBinding, prompt: Text(verbatim: "0").foregroundStyle(Theme.placeholder)) {
                Text("add.amount.a11y")
            }
            .typeStyle(.amountDisplay)
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .fixedSize()
            .focused($focus, equals: .amount)
            // Скрытый label поля VoiceOver не читает — только плейсхолдер «0».
            .accessibilityLabel(Text("add.amount.a11y"))
            Text(verbatim: money.currencySymbol)
                .typeStyle(.currencyDisplay)
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { amountWidth = $0 }
        .scaleEffect(amountScale)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .offset(y: isFlyingAway && !reduceMotion ? -Self.flyDistance : 0)
        .blur(radius: isFlyingAway && !reduceMotion ? Self.flyBlur : 0)
        .opacity(isFlyingAway ? 0 : 1)
    }

    private var amountScale: CGFloat {
        amountWidth > availableWidth && availableWidth > 0 ? availableWidth / amountWidth : 1
    }

    private var amountBinding: Binding<String> {
        Binding {
            model.amountText
        } set: { typed in
            if model.updateAmount(typed) {
                EntrySpeech.announce(String(localized: "add.amount.invalid"))
            }
        }
    }

    /// Пилюля пакета «✓ 2 траты · 21,50» → «Только что записанные».
    private var batchPill: some View {
        let batch = visibleBatch
        let total = money.string(fromMinor: batch.totalMinor, style: .plain)
        return Button {
            subSheet = .batch
        } label: {
            Label {
                Text(verbatim: L10n.format("add.batch.pill", batch.count, total))
                    .contentTransition(.numericText(value: Double(batch.count)))
            } icon: {
                Image(systemName: "checkmark")
            }
        }
        .buttonStyle(.glassCapsule(height: Theme.Size.chip, expands: false))
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(Text(verbatim: L10n.format(
            "add.batch.pill.a11y", batch.count, EntrySpeech.money(batch.totalMinor, formatter: money)
        )))
        .accessibilityHint("add.batch.pill.a11y.hint")
        .accessibilityShowsLargeContentViewer()
    }

    @ViewBuilder
    private var dateAndNote: some View {
        if isEditingNote {
            noteField
        } else {
            GlassEffectContainer(spacing: Theme.Spacing.sm) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.sm) {
                        dateSegment.fixedSize(horizontal: true, vertical: false)
                        noteButton
                    }
                    VStack(spacing: Theme.Spacing.sm) {
                        dateSegment.fixedSize(horizontal: true, vertical: false)
                        noteButton
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    private var dateSegment: some View {
        let segment = model.dateSegment()
        let picked: Date? = if case .other(let date) = segment { date } else { nil }
        let formatter = AppLanguage.current.dateFormatter(calendar: calendar, now: .now)
        return EntryDateSegment(
            segment: segment,
            pickedTitle: picked.map(formatter.short),
            pickedAccessibilityLabel: picked.map { date in
                let weekday = formatter.weekdayName(calendar.component(.weekday, from: date))
                return L10n.format("add.date.picked.a11y", "\(weekday), \(formatter.dayMonth(date))")
            },
            onSelect: selectDate
        )
    }

    /// «+ Заметка» или текст заметки с карандашом (правка, а также после ввода). Стекло-клавиша 44, как дата.
    private var noteButton: some View {
        let note = model.draft.trimmedNote
        return Button {
            isEditingNote = true
        } label: {
            Group {
                if note.isEmpty {
                    Label("add.note", systemImage: "plus")
                } else {
                    Label(note, systemImage: "pencil")
                }
            }
            .typeStyle(.callout)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.chip)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(.key)
        .accessibilityLabel(note.isEmpty ? Text("add.note.a11y") : Text(verbatim: L10n.format("edit.note.a11y", note)))
        .accessibilityHint(note.isEmpty ? Text("add.note.a11y.hint") : Text("edit.note.a11y.hint"))
        .accessibilityShowsLargeContentViewer()
    }

    /// Поле заметки 52/r14 на месте ряда даты; «Готово» возвращает к сумме.
    private var noteField: some View {
        TextField(text: $model.note, prompt: Text("add.note.placeholder").foregroundStyle(Theme.placeholder)) {
            Text("add.note")
        }
        .typeStyle(.body)
        .foregroundStyle(Theme.ink)
        .tint(Theme.ink)
        .submitLabel(.done)
        .focused($focus, equals: .note)
        .onSubmit { focus = .amount }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(minHeight: Theme.Size.field)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
        .task { focus = .note }
    }

    /// [Ещё одна | Удалить] [Сохранить] в пропорции 1 : 1,35; на крупном тексте — друг под другом.
    /// Ряд закреплён над клавиатурой, как панель: растёт только до AX1, крупнее — Large Content Viewer.
    private var actions: some View {
        GlassEffectContainer(spacing: Theme.Spacing.md) {
            ViewThatFits(in: .horizontal) {
                ProportionalHStack(weights: [1, 1.35]) { actionButtons }
                VStack(spacing: Theme.Spacing.md) { actionButtons }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if model.isNew {
            Button("add.another", action: anotherOne)
                .buttonStyle(.glassCapsule())
                .accessibilityLabel("add.another.a11y")
                .accessibilityShowsLargeContentViewer()
        } else {
            Button(action: deleteExpense) {
                Label("edit.delete", systemImage: "trash")
            }
            .buttonStyle(.glassCapsule(.destructive))
            .accessibilityLabel("edit.delete.a11y")
            .accessibilityShowsLargeContentViewer()
        }
        Button(modeKey(add: "add.save", edit: "edit.save"), action: save)
            .buttonStyle(.glassCapsule(.prominent))
            .accessibilityShowsLargeContentViewer()
    }

    @ToolbarContentBuilder
    private var keyboardToolbar: some ToolbarContent {
        if focus == .amount {
            // Отдельные клавиши — один ToolbarItem со своим рядом без общей капсулы (AGENTS.md).
            ToolbarItem(placement: .keyboard) {
                QuickAmountBar { units in
                    if model.addQuickAmount(units) { quickCount += 1 }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { quickBarTop = $0 }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// Новая категория из «Все категории» сразу выбирается, шит выбора закрывается.
    private func pickCreatedCategory(_ id: UUID) {
        var descriptor = FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let category = try? modelContext.fetch(descriptor).first else { return }
        model.pick(CategoryChoice(category))
        selectionCount += 1
        subSheet = nil
    }

    @ViewBuilder
    private func subSheetView(_ sheet: SubSheet) -> some View {
        switch sheet {
        case .picker:
            CategoryPickerSheet(
                selectedID: model.category?.id,
                keepingID: model.initialCategoryID,
                auraTones: pickerAuraTones,
                onSelect: { choice in
                    model.pick(choice)
                    selectionCount += 1
                    subSheet = nil
                },
                onCreateCategory: { name in
                    newCategory = .create(name: name)
                }
            )
            .sheet(item: $newCategory) { mode in
                CategoryEditorSheet(mode: mode) { id in
                    pickCreatedCategory(id)
                }
            }
        case .date:
            EntryDateSheet(date: model.resolvedDate()) { day in
                model.pickDate(day)
                selectionCount += 1
                subSheet = nil
            }
        case .batch:
            EntryBatchSheet(ids: model.batch.entries.map(\.id))
        }
    }

    // MARK: - Состояние

    private var store: ExpenseStore { ExpenseStore(context: modelContext) }

    private var visibleBatch: EntryBatch {
        model.visibleBatch(hiding: pendingDeletion.hiddenIDs)
    }

    private var auraTones: [GouacheTone] {
        model.category?.tone.map { [$0] } ?? []
    }

    /// «Все категории»: выбранная и частые категории, до трёх разных тонов.
    private var pickerAuraTones: [GouacheTone] {
        var tones: [GouacheTone] = []
        for tone in ([model.category] + model.frequent).compactMap({ $0?.tone }) where !tones.contains(tone) {
            tones.append(tone)
        }
        return Array(tones.prefix(AuraBackground.defaultLayout.count))
    }

    private var discardTitle: LocalizedStringKey {
        modeKey(add: "add.discard.title", edit: "edit.discard.title")
    }

    /// Строка для режима: запись (`add.*`) или правка (`edit.*`).
    private func modeKey(add: LocalizedStringKey, edit: LocalizedStringKey) -> LocalizedStringKey {
        model.isNew ? add : edit
    }

    // MARK: - Действия

    private func close() {
        if model.hasUnsavedChanges {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func selectDate(_ item: EntryDateSegment.Item) {
        let current = model.dateSegment()
        switch item {
        case .today:
            guard current != .today else { return }
            model.selectToday()
        case .yesterday:
            guard current != .yesterday else { return }
            model.selectYesterday()
        case .other:
            subSheet = .date
            return
        }
        selectionCount += 1
    }

    private func save() {
        guard !isFlyingAway else { return }
        guard model.canSave else { return rejectEmptyAmount() }
        do {
            try model.save(using: store)
        } catch {
            isShowingSaveError = true
            return
        }
        saveCount += 1
        router?.savedExpenseID = model.savedExpenseID
        EntrySpeech.announce(String(localized: "add.saved.a11y.save"))
        dismiss()
    }

    /// Сохранить, сбросить сумму, заметку и категорию; дата и клавиатура остаются.
    private func anotherOne() {
        guard !isFlyingAway else { return }
        guard model.canSave else { return rejectEmptyAmount() }
        do {
            try withAnimation(Motion.animation(Motion.enter, reduceMotion: reduceMotion)) {
                try model.saveForAnother(using: store)
            }
        } catch {
            isShowingSaveError = true
            return
        }
        anotherCount += 1
        EntrySpeech.announce(L10n.format("add.saved.a11y.another", model.batch.count))
        withAnimation(Motion.animation(Motion.anotherOne, reduceMotion: reduceMotion)) {
            isFlyingAway = true
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.resetForNextExpense()
                isFlyingAway = false
            }
            focus = .amount
        }
    }

    /// «Удалить» в правке: шит закрывается, тост с отменой показывает экран под ним.
    private func deleteExpense() {
        guard let id = model.expenseID else { return }
        pendingDeletion.schedule(
            PendingDeletion.Item(id: id, title: String(localized: "toast.deleted.title")),
            store: store
        )
        dismiss()
    }

    /// «Сохранить» без суммы: тряска, `.error`, объявление VoiceOver.
    private func rejectEmptyAmount() {
        shakeCount += 1
        EntrySpeech.announce(String(localized: "add.amount.empty.a11y"))
        focus = .amount
    }
}

#if DEBUG
extension ExpenseEntryView {
    /// `-debugSheet filled` и `-debugSubsheet …` (см. `ExpenseSheetDebug`).
    private func applyDebugRequest() async {
        if ExpenseSheetDebug.isFilledRequested(), model.isNew, model.batch.isEmpty {
            let swatches = model.swatches
            for (amount, index) in [("9", 1), ("12,5", 2)] where swatches.indices.contains(index) {
                model.updateAmount(amount)
                model.toggle(swatches[index])
                try? model.saveForAnother(using: store)
                model.resetForNextExpense()
            }
            model.updateAmount("12,50")
            if let supermarket = try? store.allCategories().first(where: { $0.name == "Супермаркет" }) {
                model.pick(CategoryChoice(supermarket))
            } else if let first = swatches.first {
                model.toggle(first)
            }
        }
        guard let sheet = ExpenseSheetDebug.requestedSubSheet() else { return }
        try? await Task.sleep(for: .seconds(3)) // клавиатура успевает выехать
        subSheet = sheet
    }
}
#endif
