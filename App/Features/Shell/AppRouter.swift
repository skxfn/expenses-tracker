import Foundation
import Observation
import ExpenseCore

/// Вкладки приложения. Настройки — пушем из ⚙, не вкладкой.
enum AppTab: String, Hashable, CaseIterable {
    case expenses
    case calendar
    case statistics
}

/// Экраны, которые открываются пушем внутри вкладки. Назначения регистрирует корень (`ContentView`),
/// экраны только ставят `NavigationLink(value:)`.
enum AppRoute: Hashable {
    /// Настройки — пушем из ⚙ в шапке главной.
    case settings
}

/// Шит поверх всего приложения. Показывает корень (`ContentView`), экраны только просят.
enum AppSheet: Identifiable, Hashable {
    case expense(ExpenseSheet.Mode)

    var id: String {
        switch self {
        case .expense(let mode): "expense-\(mode.id)"
        }
    }
}

/// Переход в статистику с тем же периодом и раскрытой категорией (тап по плитке на главной).
struct StatisticsFocus: Hashable {
    let period: StatsPeriod
    /// Категория верхнего уровня; `nil` — без раскрытия.
    let groupID: UUID?
}

/// Навигация между вкладками и общие шиты. Кладётся в окружение корнем: `@Environment(AppRouter.self)`.
@Observable
final class AppRouter {
    var tab: AppTab
    var sheet: AppSheet?
    /// Задание для статистики; экран статистики забирает его и обнуляет.
    var statisticsFocus: StatisticsFocus?
    /// Трата, только что записанная «Сохранить» в шите: главная подсвечивает её строку (save-reward) и обнуляет.
    var savedExpenseID: UUID?

    init(tab: AppTab = .expenses) {
        self.tab = tab
    }

    func presentAdd(date: Date? = nil) {
        sheet = .expense(.add(date: date))
    }

    func presentEdit(expenseID: UUID) {
        sheet = .expense(.edit(expenseID: expenseID))
    }

    func openStatistics(period: StatsPeriod, groupID: UUID?) {
        statisticsFocus = StatisticsFocus(period: period, groupID: groupID)
        tab = .statistics
    }
}
