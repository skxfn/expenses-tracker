import SwiftData
import SwiftUI
import ExpenseCore

/// Строка траты с действиями ленты (DESIGN.md → Feed Row): тап — правка (`AppRouter.presentEdit`), свайп вправо —
/// «Повторить» (такая же трата на сейчас), влево — «Удалить» с тостом «Отменить» (`PendingDeletion`); те же
/// действия — у VoiceOver (`feed.row.a11y.*`). Свайпы работают только в `List`; в `ScrollView` остаются тап
/// и действия VoiceOver. Ошибку повтора показывает экран (`onError`).
struct ExpenseFeedRow: View {
    let data: ExpenseRowData
    /// Текст ошибки «Повторить» для алерта экрана (`UserFacingError`).
    var onError: (String) -> Void = { _ in }

    @Environment(AppRouter.self) private var router
    @Environment(PendingDeletion.self) private var pendingDeletion
    @Environment(\.modelContext) private var modelContext
    @State private var repeatCount = 0

    var body: some View {
        Button {
            router.presentEdit(expenseID: data.id)
        } label: {
            ExpenseRow(data: data)
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: repeatExpense) {
                Label("feed.swipe.repeat", systemImage: "arrow.clockwise")
            }
            .tint(Theme.graphic)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: delete) {
                Label("feed.swipe.delete", systemImage: "trash")
            }
        }
        .accessibilityAction(named: Text("feed.row.a11y.delete"), delete)
        .accessibilityAction(named: Text("feed.row.a11y.repeat"), repeatExpense)
        .sensoryFeedback(Haptic.success, trigger: repeatCount)
    }

    private func delete() {
        let item = PendingDeletion.Item(id: data.id, title: String(localized: "toast.deleted.title"))
        pendingDeletion.schedule(item, store: ExpenseStore(context: modelContext))
    }

    /// «Повторить»: такая же трата (сумма, категория, заметка) с датой «сейчас».
    private func repeatExpense() {
        let store = ExpenseStore(context: modelContext)
        do {
            guard let expense = try store.expense(id: data.id) else { return }
            try store.addExpense(amountMinor: expense.amountMinor, date: .now, note: expense.note, category: expense.category)
            repeatCount += 1
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }
}
