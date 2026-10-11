import SwiftData
import SwiftUI
import ExpenseCore

/// Шит «Только что записанные» (`add.batch.sheet`): траты пакета строками ленты.
/// Свайп «Удалить» — без вопроса, с тостом отмены прямо в этом шите (шит записи и лента под ним закрыты).
struct EntryBatchSheet: View {
    let ids: [UUID]

    @Environment(\.modelContext) private var modelContext
    @Environment(PendingDeletion.self) private var pendingDeletion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows) { row in
                    ExpenseRow(data: row)
                        .listRowBackground(Theme.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { delete(row) } label: {
                                Label("feed.swipe.delete", systemImage: "trash")
                            }
                        }
                        .accessibilityAction(named: "feed.row.a11y.delete") { delete(row) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .sheetHeader("add.batch.sheet", onClose: { dismiss() })
        }
        .glassToast(isPresented: isToastShown, bottomPadding: Theme.Spacing.sm) {
            GlassToast(
                message: "toast.deleted.title",
                action: .init(title: "toast.deleted.undo", handler: undo),
                onPressingChanged: { [id = pendingDeletion.item?.id] in
                    $0 ? pendingDeletion.pause(for: id) : pendingDeletion.resume(for: id)
                }
            )
            // Как `deletionToast`: «Трата удалена», действие «Отменить»; новое удаление — новый тост с фокусом.
            .accessibilityLabel("toast.deleted.a11y")
            .accessibilityRemoveTraits(.isButton)
            .accessibilityAction(named: "toast.deleted.a11y.undo", undo)
            .id(pendingDeletion.item?.id)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvasElevated)
    }

    /// Траты пакета, которые ещё есть и не ждут удаления; новые сверху, как в ленте.
    private var rows: [ExpenseRowData] {
        let store = ExpenseStore(context: modelContext)
        let hidden = pendingDeletion.hiddenIDs
        return ids.reversed()
            .filter { !hidden.contains($0) }
            .compactMap { id in (try? store.expense(id: id)) ?? nil }
            .map(ExpenseRowData.init)
    }

    private var isToastShown: Bool {
        pendingDeletion.item.map { ids.contains($0.id) } ?? false
    }

    private func undo() {
        pendingDeletion.undo()
        EntrySpeech.announce(String(localized: "toast.undone.a11y"))
    }

    private func delete(_ row: ExpenseRowData) {
        pendingDeletion.schedule(
            PendingDeletion.Item(id: row.id, title: String(localized: "toast.deleted.title")),
            store: ExpenseStore(context: modelContext)
        )
        EntrySpeech.announce(String(localized: "toast.deleted.a11y"))
    }
}
