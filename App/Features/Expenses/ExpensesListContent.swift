import Foundation
import ExpenseCore

/// Расходы одного дня.
struct ExpenseDaySection: Identifiable {
    /// Начало дня.
    let day: Date
    /// «Сегодня», «Вчера», «6 октября».
    let title: String
    /// От новых к старым.
    let expenses: [Expense]
    let totalMinor: Int64

    var id: Date { day }
}

/// Данные экрана «Расходы»: секции по дням и итог текущего месяца.
struct ExpensesListContent {
    let sections: [ExpenseDaySection]
    let monthTotalMinor: Int64
    /// «Октябрь»
    let monthTitle: String

    /// - Parameter expenses: отсортированы от новых к старым.
    init(expenses: [Expense], now: Date = .now, calendar: Calendar = .autoupdatingCurrent) {
        let dates = RussianDateFormatter(calendar: calendar, now: now)
        let byDay = Dictionary(grouping: expenses) { calendar.startOfDay(for: $0.date) }
        sections = byDay
            .map { day, items in
                ExpenseDaySection(
                    day: day,
                    title: dates.title(for: .current(.day, now: day, calendar: calendar)).text,
                    expenses: items,
                    totalMinor: items.reduce(0) { $0 + $1.amountMinor }
                )
            }
            .sorted { $0.day > $1.day }

        let month = StatsPeriod.current(.month, now: now, calendar: calendar)
        monthTotalMinor = expenses.reduce(0) { total, expense in
            month.contains(expense.date) ? total + expense.amountMinor : total
        }
        monthTitle = dates.title(for: month).text
    }
}
