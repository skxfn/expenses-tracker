import Foundation

/// Итог импорта из Monefy.
public struct MonefyImportReport: Equatable, Sendable {
    /// Записано новых трат.
    public var imported = 0
    /// Пропущены: такая трата уже есть в приложении (тот же день, сумма, категория и заметка).
    public var duplicates = 0
    /// Пропущены по выбору «Не переносить».
    public var excluded = 0
    /// Строки файла, которые не траты: доходы, переводы и начальные остатки.
    public var notExpenses = 0

    public init(imported: Int = 0, duplicates: Int = 0, excluded: Int = 0, notExpenses: Int = 0) {
        self.imported = imported
        self.duplicates = duplicates
        self.excluded = excluded
        self.notExpenses = notExpenses
    }
}

/// Почему импорт не начался. UI до этого не доводит: кнопка неактивна, пока не выбрано всё,
/// а выбранную категорию могли удалить только в другом окне.
public enum MonefyImportError: Error, Equatable, Sendable {
    /// Для категории Monefy ничего не выбрано.
    case unmappedCategory(String)
    /// Выбранной категории приложения уже нет.
    case missingCategory(UUID)
}

/// Импорт трат из файла Monefy по сопоставлению категорий.
@MainActor
public enum MonefyImporter {
    /// Записывает траты файла через `ExpenseStore` одним сохранением: всё или ничего.
    ///
    /// Повторный импорт того же файла ничего не удваивает: трата пропускается, если в приложении уже есть
    /// трата с тем же днём, суммой, категорией назначения и заметкой. Совпадения считаются поштучно: две
    /// одинаковые траты в файле (два такси за день) при одной такой в приложении дадут одну новую.
    /// - Parameter calendar: день траты — полдень в этом календаре; по нему же сравниваются дни.
    @discardableResult
    public static func apply(
        _ plan: MonefyImportPlan,
        mapping: [String: MonefyCategoryTarget],
        store: ExpenseStore,
        calendar: Calendar = .current
    ) throws -> MonefyImportReport {
        try apply(plan, mapping: mapping, store: store, calendar: calendar, beforeCommit: {})
    }

    /// `beforeCommit` — точка для проверки отката в тестах (см. `ExpenseStore.addExpenses`).
    static func apply(
        _ plan: MonefyImportPlan,
        mapping: [String: MonefyCategoryTarget],
        store: ExpenseStore,
        calendar: Calendar,
        beforeCommit: () throws -> Void
    ) throws -> MonefyImportReport {
        if let unmapped = plan.groups.first(where: { mapping[$0.name] == nil }) {
            throw MonefyImportError.unmappedCategory(unmapped.name)
        }
        let categories = Dictionary(try store.allCategories().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for case .category(let id) in mapping.values where categories[id] == nil {
            throw MonefyImportError.missingCategory(id)
        }

        var report = MonefyImportReport(notExpenses: plan.notExpenseCount)
        var existing = try existingKeys(in: plan, store: store, calendar: calendar)
        var additions: [ExpenseStore.NewExpense] = []
        for expense in plan.file.expenses {
            let category: ExpenseCategory?
            switch mapping[expense.category] {
            case .skip, nil:
                report.excluded += 1
                continue
            case .uncategorized:
                category = nil
            case .category(let id):
                category = categories[id]
            }
            let key = DuplicateKey(day: expense.day, amountMinor: expense.amountMinor, categoryID: category?.id, note: expense.note)
            if let count = existing[key], count > 0 {
                existing[key] = count - 1
                report.duplicates += 1
                continue
            }
            guard let date = expense.day.noon(in: calendar) else { continue }
            additions.append(.init(amountMinor: expense.amountMinor, date: date, note: expense.note, category: category))
        }
        try store.addExpenses(additions, beforeCommit: beforeCommit)
        report.imported = additions.count
        return report
    }

    /// Признаки повтора: день, сумма, категория назначения, заметка без пробелов по краям.
    struct DuplicateKey: Hashable {
        let day: MonefyCSV.Day
        let amountMinor: Int64
        let categoryID: UUID?
        let note: String
    }

    /// Траты приложения за дни файла — сколько каких.
    private static func existingKeys(
        in plan: MonefyImportPlan,
        store: ExpenseStore,
        calendar: Calendar
    ) throws -> [DuplicateKey: Int] {
        guard
            let period = plan.period,
            let start = period.lowerBound.start(in: calendar),
            let lastStart = period.upperBound.start(in: calendar),
            let end = calendar.date(byAdding: .day, value: 1, to: lastStart)
        else { return [:] }
        var counts: [DuplicateKey: Int] = [:]
        for expense in try store.expenses(in: DateInterval(start: start, end: end)) {
            let key = DuplicateKey(
                day: MonefyCSV.Day(expense.date, calendar: calendar),
                amountMinor: expense.amountMinor,
                categoryID: expense.category?.id,
                note: expense.note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            counts[key, default: 0] += 1
        }
        return counts
    }
}
