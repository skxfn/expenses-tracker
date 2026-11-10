import SwiftData
import SwiftUI
import ExpenseCore

/// Черновики на проверке: у каждой траты правятся сумма, категория, дата и заметка, свайпом — убрать.
/// Для чека сверху — магазин, дата и режим («По категориям · Каждая позиция · Одной тратой»), внизу —
/// расхождение с итогом и «Не разобрано». «Записать N» — одним сохранением.
struct DraftReviewView: View {
    private enum Picker: Identifiable {
        case category(UUID)
        case date(UUID)

        var id: String {
            switch self {
            case .category(let id): "category-\(id)"
            case .date(let id): "date-\(id)"
            }
        }
    }

    @Bindable var model: DraftReviewModel
    let onEditInput: () -> Void
    let onSaved: () -> Void

    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder), SortDescriptor(\ExpenseCategory.createdAt)])
    private var categories: [ExpenseCategory]

    @State private var picker: Picker?
    @State private var newCategory: CategoryEditorMode?
    @State private var newCategoryDraftID: UUID?
    @State private var pendingMode: ReceiptGroupingMode?
    @State private var isConfirmingBack = false
    @State private var saveError: String?
    @State private var saveCount = 0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var money
    @Environment(\.calendar) private var calendar
    @Environment(AppRouter.self) private var router: AppRouter?

    var body: some View {
        let choices = Dictionary(categories.map { ($0.id, CategoryChoice($0)) }, uniquingKeysWith: { first, _ in first })
        List {
            // Шапка и подвал — обычные строки: закреплённые заголовки секций в `.plain` ложатся полосой фона.
            header
                .listRowBackground(Theme.canvasElevated)
                .listRowSeparator(.hidden)
            ForEach(model.drafts) { item in
                DraftRow(
                    item: item,
                    choice: item.draft.categoryID.flatMap { choices[$0] },
                    dateText: dateText(item.draft.date),
                    currency: money.currencySymbol,
                    onAmount: { model.setAmountText($0, for: item.id) },
                    onNote: { model.setNote($0, for: item.id) },
                    onCategory: { picker = .category(item.id) },
                    onDate: { picker = .date(item.id) }
                )
                .listRowBackground(Theme.canvasElevated)
                .listRowSeparatorTint(Theme.separator)
                .swipeActions(edge: .trailing) {
                    Button("assistant.review.remove", role: .destructive) {
                        withAnimation(Motion.select) { model.remove(item.id) }
                    }
                }
            }
            if model.mismatchMinor != nil || !model.result.unparsed.isEmpty {
                footer
                    .listRowBackground(Theme.canvasElevated)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Button("assistant.review.back", action: requestBack)
                    .buttonStyle(.glassCapsule())
                Button(L10n.format("assistant.review.save", model.drafts.count), action: save)
                    .buttonStyle(.glassCapsule(.prominent))
                    .disabled(!model.canSave)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.md)
        }
        .sheet(item: $picker) { picker in
            pickerView(picker)
        }
        .confirmationDialog("assistant.review.mode.confirm", isPresented: isConfirmingMode, titleVisibility: .visible) {
            Button("assistant.review.mode.apply", role: .destructive) {
                if let pendingMode { model.setMode(pendingMode) }
                pendingMode = nil
            }
            Button("assistant.review.mode.keep", role: .cancel) { pendingMode = nil }
        }
        .confirmationDialog("assistant.review.back.confirm", isPresented: $isConfirmingBack, titleVisibility: .visible) {
            Button("assistant.review.back.apply", role: .destructive, action: onEditInput)
            Button("assistant.review.back.keep", role: .cancel) {}
        }
        .errorAlert($saveError)
        .sensoryFeedback(Haptic.success, trigger: saveCount)
    }

    // MARK: - Шапка и подвал

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let receipt = model.result.receipt {
                Text(verbatim: receiptLine(receipt))
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                GlassSegmentedControl(
                    title: "assistant.review.mode",
                    selection: Binding(get: { model.mode }, set: requestMode),
                    items: [
                        .init(value: .byCategory, title: "assistant.review.mode.byCategory"),
                        .init(value: .perItem, title: "assistant.review.mode.perItem"),
                        .init(value: .single, title: "assistant.review.mode.single"),
                    ]
                )
            }
            Text(verbatim: L10n.format("assistant.review.total", model.drafts.count, money.string(fromMinor: model.totalMinor)))
                .typeStyle(.callout)
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let difference = model.mismatchMinor {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(verbatim: L10n.format("assistant.review.mismatch", money.string(fromMinor: abs(difference))))
                        .typeStyle(.callout)
                        .foregroundStyle(Theme.ink)
                    if difference > 0 {
                        Button("assistant.review.addDifference") {
                            withAnimation(Motion.select) { model.addDifference() }
                        }
                        .typeStyle(.footnoteStrong)
                        .foregroundStyle(Theme.ink)
                    }
                }
            }
            if !model.result.unparsed.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("assistant.review.unparsed")
                        .typeStyle(.footnoteStrong)
                        .foregroundStyle(Theme.secondary)
                    ForEach(Array(model.result.unparsed.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .typeStyle(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Выбор категории и даты

    @ViewBuilder
    private func pickerView(_ picker: Picker) -> some View {
        switch picker {
        case .category(let draftID):
            CategoryPickerSheet(
                selectedID: model.drafts.first { $0.id == draftID }?.draft.categoryID,
                keepingID: nil,
                auraTones: [],
                onSelect: { choice in
                    model.setCategory(choice.id, for: draftID)
                    self.picker = nil
                },
                onCreateCategory: { name in
                    newCategoryDraftID = draftID
                    newCategory = .create(name: name)
                }
            )
            .sheet(item: $newCategory) { mode in
                CategoryEditorSheet(mode: mode) { id in
                    if let draftID = newCategoryDraftID { model.setCategory(id, for: draftID) }
                    newCategory = nil
                    self.picker = nil
                }
            }
        case .date(let draftID):
            let current = model.drafts.first { $0.id == draftID }?.draft.date ?? .today
            EntryDateSheet(date: current.resolved(now: .now, calendar: calendar)) { day in
                model.setDate(EntryDate.picked(day, now: .now, calendar: calendar), for: draftID)
                self.picker = nil
            }
        }
    }

    private var isConfirmingMode: Binding<Bool> {
        Binding(get: { pendingMode != nil }, set: { if !$0 { pendingMode = nil } })
    }

    /// Смена режима пересобирает черновики из позиций: правки пропадут — спросить.
    /// Правленые черновики при возврате к вводу пропадут — сначала спросить.
    private func requestBack() {
        if model.hasEdits {
            isConfirmingBack = true
        } else {
            onEditInput()
        }
    }

    private func requestMode(_ mode: ReceiptGroupingMode) {
        if model.hasEdits {
            pendingMode = mode
        } else {
            withAnimation(Motion.select) { model.setMode(mode) }
        }
    }

    // MARK: - Тексты

    private func dateText(_ date: EntryDate) -> String {
        switch date.segment(now: .now, calendar: calendar) {
        case .today: String(localized: "add.date.today")
        case .yesterday: String(localized: "add.date.yesterday")
        case .other(let day): AppLanguage.current.dateFormatter(calendar: calendar, now: .now).short(day)
        }
    }

    /// «Евроопт · 8 ноя · итог 30,83 ⃅» — данные чека, без своих слов, кроме «итог».
    private func receiptLine(_ receipt: ReceiptSummary) -> String {
        var parts: [String] = []
        if let store = receipt.store { parts.append(store) }
        if let day = receipt.day { parts.append(AppLanguage.current.dateFormatter(calendar: calendar, now: .now).short(day)) }
        if let total = receipt.totalMinor { parts.append(L10n.format("assistant.review.receiptTotal", money.string(fromMinor: total))) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Сохранение

    private func save() {
        do {
            let ids = try model.save(using: ExpenseStore(context: modelContext))
            saveCount += 1
            router?.savedExpenseID = ids.first
            onSaved()
        } catch {
            saveError = UserFacingError.message(for: error)
        }
    }
}

/// Строка черновика: плашка категории, заметка, «категория · дата», сумма; ниже — откуда взята и что проверить.
private struct DraftRow: View {
    let item: AssistantDraft
    let choice: CategoryChoice?
    let dateText: String
    let currency: String
    let onAmount: (String) -> Void
    let onNote: (String) -> Void
    let onCategory: () -> Void
    let onDate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Button(action: onCategory) {
                    CategoryPlaque(iconName: choice?.iconName ?? CategoryPaint.uncategorizedIconName, tone: choice?.tone)
                }
                .buttonStyle(.pressable(Motion.PressScale.circle))
                .accessibilityLabel(Text(verbatim: choice?.line ?? String(localized: "feed.row.noCategory")))
                .accessibilityHint(Text("assistant.review.category.a11y.hint"))

                VStack(alignment: .leading, spacing: 2) {
                    TextField("assistant.review.note.placeholder", text: Binding(get: { item.draft.note }, set: { onNote($0) }))
                        .typeStyle(.body)
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 4) {
                        Button(action: onCategory) {
                            Text(verbatim: choice?.line ?? String(localized: "feed.row.noCategory"))
                                .foregroundStyle(item.issues.contains(.categoryMissing) ? Theme.destructive : Theme.secondary)
                        }
                        Text(verbatim: "·").foregroundStyle(Theme.tertiary).accessibilityHidden(true)
                        Button(action: onDate) {
                            Text(verbatim: dateText).foregroundStyle(Theme.secondary)
                        }
                        .accessibilityHint(Text("assistant.review.date.a11y.hint"))
                    }
                    .typeStyle(.footnote)
                    .buttonStyle(.plain)
                    .lineLimit(1)
                }

                Spacer(minLength: Theme.Spacing.sm)

                HStack(spacing: 4) {
                    TextField("assistant.review.amount.placeholder", text: Binding(get: { item.draft.amountText }, set: { onAmount($0) }))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .typeStyle(.amountInlineStrong)
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: 56, maxWidth: 110)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel(Text("assistant.review.amount.a11y"))
                    Text(verbatim: currency)
                        .typeStyle(.amountInline)
                        .foregroundStyle(Theme.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    item.issues.contains(.amountMissing) ? Theme.destructive.opacity(0.12) : Theme.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.chipInner, style: .continuous)
                )
            }
            if !issueText.isEmpty || !item.source.isEmpty {
                Text(verbatim: [issueText, item.source].filter { !$0.isEmpty }.joined(separator: " · "))
                    .typeStyle(.caption)
                    .foregroundStyle(issueText.isEmpty ? Theme.tertiary : Theme.destructive)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    /// Что проверить: дата сдвинута или слишком старая (сумма и категория подсвечены на месте).
    private var issueText: String {
        if item.issues.contains(.dateAdjusted) { return String(localized: "assistant.review.dateAdjusted") }
        if item.issues.contains(.dateOld) { return String(localized: "assistant.review.dateOld") }
        return ""
    }
}
