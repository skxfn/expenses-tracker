import SwiftData
import SwiftUI
import ExpenseCore

/// Точка входа в шит записи и правки траты. Показывает корень через `AppRouter`.
/// Внешний вид — этап «Запись» (макеты 06–08); сейчас внутри временная форма.
struct ExpenseSheet: View {
    enum Mode: Hashable {
        /// `date == nil` — сегодня; иначе запись на выбранный день (календарь).
        case add(date: Date?)
        case edit(expenseID: UUID)

        var id: String {
            switch self {
            case .add(let date): "add-\(date?.timeIntervalSinceReferenceDate ?? 0)"
            case .edit(let id): "edit-\(id.uuidString)"
            }
        }
    }

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var money
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ExpenseFormView(expense: expense, formatter: money) {}
    }

    private var expense: Expense? {
        guard case .edit(let id) = mode else { return nil }
        return try? ExpenseStore(context: modelContext).expense(id: id)
    }
}
