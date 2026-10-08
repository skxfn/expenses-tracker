#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import ExpenseCore

/// Демо-данные для проверки статистики (только отладочная сборка).
///
/// Пишет через `BackupImporter` одной транзакцией: сотни отдельных `ExpenseStore.addExpense`
/// с сохранением каждого заметно подвешивали бы интерфейс. Валидация при этом та же.
enum DemoData {
    /// Как часто и на какие суммы тратят в категории.
    private struct Profile {
        /// Вероятность траты в обычный день (в выходные — в полтора раза выше).
        var dailyChance: Double = 0
        /// Фиксированный платёж раз в месяц в этот день.
        var monthlyDay: Int?
        let range: ClosedRange<Double>
        var notes: [String] = []
    }

    /// Профили по именам базовых категорий; для остальных — `fallbackProfile`.
    private static let profiles: [String: Profile] = [
        "Продукты": Profile(dailyChance: 0.7, range: 8...75, notes: ["Евроопт", "Рынок", "Гиппо", ""]),
        "Кафе и рестораны": Profile(dailyChance: 0.3, range: 6...45, notes: ["Кофе", "Обед", "Пицца", ""]),
        "Транспорт": Profile(dailyChance: 0.55, range: 0.9...12, notes: ["Метро", "Такси", ""]),
        "Жильё и ЖКХ": Profile(monthlyDay: 5, range: 150...240, notes: ["Коммуналка"]),
        "Связь и интернет": Profile(monthlyDay: 12, range: 25...32, notes: ["Интернет и мобильный"]),
        "Здоровье": Profile(dailyChance: 0.06, range: 8...90, notes: ["Аптека", ""]),
        "Развлечения": Profile(dailyChance: 0.1, range: 12...60, notes: ["Кино", "Боулинг", "Концерт"]),
        "Одежда": Profile(dailyChance: 0.04, range: 40...220),
        "Подписки": Profile(monthlyDay: 20, range: 9...20, notes: ["Музыка", "Облако"]),
        "Подарки": Profile(dailyChance: 0.03, range: 25...120),
        "Образование": Profile(dailyChance: 0.03, range: 15...90, notes: ["Книги", "Курс"]),
        "Другое": Profile(dailyChance: 0.08, range: 3...35)
    ]
    private static let fallbackProfile = Profile(dailyChance: 0.08, range: 5...50)

    /// Добавляет траты за последние `days` дней по активным категориям к текущим данным.
    static func fill(context: ModelContext, currencyCode: String, days: Int = 92) throws {
        let categories = try ExpenseStore(context: context).activeCategories()
        let payload = makePayload(categories: categories, currencyCode: currencyCode, days: days)
        try BackupImporter.apply(payload, to: context, mode: .merge)
    }

    /// Удаляет все категории и расходы и заново создаёт базовые категории — как после установки.
    static func eraseAll(context: ModelContext, defaults: UserDefaults = .standard) throws {
        let empty = BackupPayload(
            exportedAt: .now,
            currencyCode: CurrencySettings.currencyCode(in: defaults),
            categories: [],
            expenses: []
        )
        try BackupImporter.apply(empty, to: context, mode: .replace)
        defaults.removeObject(forKey: SettingsKeys.didSeedDefaultCategories)
        try ExpenseStore(context: context).seedDefaultCategoriesIfNeeded(defaults: defaults)
    }

    private static func makePayload(
        categories: [ExpenseCategory],
        currencyCode: String,
        days: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> BackupPayload {
        let targets: [(id: UUID?, profile: Profile)] = categories.isEmpty
            ? [(nil, fallbackProfile)]
            : categories.map { ($0.id, profiles[$0.name] ?? fallbackProfile) }
        let today = calendar.startOfDay(for: now)
        var expenses: [BackupPayload.ExpenseRecord] = []

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekendFactor = calendar.isDateInWeekend(day) ? 1.5 : 1
            let dayOfMonth = calendar.component(.day, from: day)

            for (categoryID, profile) in targets {
                let happens = profile.monthlyDay.map { $0 == dayOfMonth }
                    ?? (Double.random(in: 0..<1) < profile.dailyChance * weekendFactor)
                guard happens, let amountMinor = Money.minor(fromMajor: Decimal(Double.random(in: profile.range))) else {
                    continue
                }
                // С 8:00 до 22:00, но не позже текущего момента.
                let date = min(day.addingTimeInterval(.random(in: 8 * 3600...22 * 3600)), now)
                expenses.append(BackupPayload.ExpenseRecord(
                    id: UUID(),
                    amountMinor: amountMinor,
                    date: date,
                    note: profile.notes.randomElement() ?? "",
                    categoryID: categoryID,
                    createdAt: date,
                    updatedAt: date
                ))
            }
        }
        return BackupPayload(exportedAt: now, currencyCode: currencyCode, categories: [], expenses: expenses)
    }
}

/// Секция настроек для проверки статистики: демо-данные и полная очистка.
struct DebugDataSection: View {
    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingErase = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Button("Заполнить демо-данными") {
                perform { try DemoData.fill(context: modelContext, currencyCode: currencyCode) }
            }
            .errorAlert($errorMessage)
            Button("Удалить все данные", role: .destructive) {
                isConfirmingErase = true
            }
            .confirmationDialog(
                "Удалить все категории и расходы?",
                isPresented: $isConfirmingErase,
                titleVisibility: .visible
            ) {
                Button("Удалить всё", role: .destructive) {
                    perform { try DemoData.eraseAll(context: modelContext) }
                }
            } message: {
                Text("Базовые категории создадутся заново, как после установки.")
            }
        } header: {
            Text("Отладка")
        } footer: {
            Text("Только в отладочной сборке. Демо-данные — траты за ≈3 месяца по активным категориям, добавляются к текущим.")
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
