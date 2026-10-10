import SwiftUI
import ExpenseCore

/// «Крупнейшие траты» (`04-stats`): строки как в ленте (`ExpenseRow`: иконка подкатегории, §8 п. 6),
/// подпись — «чт, 8 окт · Кафе» (`stats.top.meta`); без заметки заголовок — имя подкатегории (`stats.top.noNote`).
/// Тап открывает правку траты.
struct StatsTopSection: View {
    let rows: [ExpenseRowData]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                Button {
                    onSelect(row.id)
                } label: {
                    ExpenseRow(data: row)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable(Motion.PressScale.row))
            }
        }
    }
}

extension ExpenseRowData {
    /// Строка топа: как в ленте, но подпись — дата и категория (`stats.top.meta`).
    init(top expense: Expense, dates: any DateTextFormatter) {
        let base = ExpenseRowData(expense)
        let group = expense.category?.parent ?? expense.category
        let date = dates.shortWithWeekday(expense.date)
        id = base.id
        iconName = base.iconName
        tone = base.tone
        title = base.title
        amountMinor = base.amountMinor
        self.date = base.date
        let note = expense.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let group, !(note.isEmpty && expense.category?.parent == nil) {
            subtitle = L10n.format("stats.top.meta", date, group.name)
        } else if group != nil || base.title == String(localized: "feed.row.noCategory") {
            // Заголовок уже называет категорию («Кафе», «Без категории») — подпись только датой.
            subtitle = date
        } else {
            subtitle = L10n.format("stats.top.meta", date, String(localized: "stats.legacy.uncategorized"))
        }
    }
}
