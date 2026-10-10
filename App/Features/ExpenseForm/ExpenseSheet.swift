import SwiftData
import SwiftUI
import ExpenseCore

/// Точка входа в шит записи и правки траты. Показывает корень через `AppRouter`;
/// зум-переход из «+» делает оболочка. Сам шит — `ExpenseEntryView` (макеты 06–08).
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

    var body: some View {
        ExpenseEntryView(model: ExpenseFormModel(
            mode: mode,
            store: ExpenseStore(context: modelContext),
            formatter: money
        ))
    }
}

#if DEBUG
/// Аргументы запуска для скриншотов шита без касаний:
/// `-debugSheet add|edit|filled` — открыть шит сразу (`edit` — последняя трата; `filled` — как макет `06-add`:
/// пакет из двух трат, сумма 12,50 и первый образец), `-debugSubsheet picker|date|batch` — поверх него.
enum ExpenseSheetDebug {
    static func requestedMode(context: ModelContext, defaults: UserDefaults = .standard) -> ExpenseSheet.Mode? {
        switch defaults.string(forKey: "debugSheet") {
        case "add":
            return .add(date: nil)
        case "filled":
            seedSubcategoriesIfNeeded(store: ExpenseStore(context: context))
            return .add(date: nil)
        case "edit":
            let latest = try? ExpenseStore(context: context).recentExpenses(limit: 1).first
            return latest.map { .edit(expenseID: $0.id) }
        default:
            return nil
        }
    }

    static func isFilledRequested(defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: "debugSheet") == "filled"
    }

    /// Подкатегории для макетов `06`/`07`, если в базе их ещё нет (демо-данные пока без подкатегорий).
    static func seedSubcategoriesIfNeeded(store: ExpenseStore) {
        let samples = [
            "Продукты": [("Супермаркет", "shopping-cart-1-fill"), ("Рынок", "basket-fill")],
            "Кафе": [("Обеды", "fork-knife-fill"), ("Кофе", "teacup-fill")],
        ]
        guard let groups = try? store.topLevelCategories() else { return }
        for group in groups where group.children.isEmpty {
            for (name, icon) in samples[group.name] ?? [] {
                _ = try? store.addSubcategory(name: name, iconName: icon, parent: group)
            }
        }
    }

    static func requestedSubSheet(defaults: UserDefaults = .standard) -> ExpenseEntryView.SubSheet? {
        defaults.string(forKey: "debugSubsheet").flatMap(ExpenseEntryView.SubSheet.init(rawValue:))
    }
}
#endif
