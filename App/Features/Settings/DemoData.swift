#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import ExpenseCore

/// Демо-данные для проверки главной, статистики и календаря (только отладочная сборка).
///
/// Категории — базовые (`DefaultCategories`) с подкатегориями, траты — ≈ 3 месяца: часть с заметками,
/// часть в категории без подкатегории, пара без категории, крупные покупки для «Крупнейших трат»,
/// пустые дни. Случайность с постоянным зерном: при одинаковой дате данные одинаковые (для скриншотов).
/// Траты пишутся через `BackupImporter` одной транзакцией: сотни отдельных `ExpenseStore.addExpense`
/// с сохранением каждого заметно подвешивали бы интерфейс. Валидация при этом та же.
enum DemoData {
    /// Куда пишется доля трат категории: подкатегория по имени или сама категория (`nil` — «без подкатегории»).
    private struct Leaf {
        let subcategory: String?
        let weight: Double
        /// Свой диапазон суммы, Br; `nil` — диапазон категории.
        var range: ClosedRange<Double>?
        /// Заметки; пустая строка — трата без заметки.
        var notes: [String] = [""]
    }

    /// Как часто и на какие суммы тратят в категории.
    private struct Profile {
        /// Вероятность траты в обычный день (в выходные — в полтора раза выше).
        var dailyChance: Double = 0
        /// Фиксированный платёж раз в месяц в этот день.
        var monthlyDay: Int?
        let range: ClosedRange<Double>
        var leaves: [Leaf]
    }

    /// Подкатегории базовых категорий: имя и иконка MingCute.
    private static let subcategories: [String: [(name: String, icon: String)]] = [
        "Продукты": [("Супермаркет", "shopping-cart-1-fill"), ("Рынок", "apple-fruit-fill"), ("Хлеб и выпечка", "bread-fill")],
        "Кафе": [("Обеды", "fork-knife-fill"), ("Кофе", "teacup-fill"), ("Доставка", "pizza-fill")],
        "Транспорт": [("Такси", "car-fill"), ("Метро", "train-fill")],
        "Здоровье": [("Аптека", "first-aid-kit-fill")],
        "Подарки": [("Друзья", "cake-fill")]
    ]

    /// Профили по именам базовых категорий; для остальных — `fallbackProfile`.
    private static let profiles: [String: Profile] = [
        "Продукты": Profile(dailyChance: 0.7, range: 6...70, leaves: [
            Leaf(subcategory: "Супермаркет", weight: 0.5, notes: ["Евроопт", "Гиппо", "Корона", "", ""]),
            Leaf(subcategory: "Рынок", weight: 0.15, notes: ["Комаровка", "Овощи и фрукты", ""]),
            Leaf(subcategory: "Хлеб и выпечка", weight: 0.15, range: 2...12, notes: ["", "Круассаны"]),
            Leaf(subcategory: nil, weight: 0.2, range: 2...15, notes: ["", "Вода", "Молоко"])
        ]),
        "Кафе": Profile(dailyChance: 0.35, range: 5...40, leaves: [
            Leaf(subcategory: "Обеды", weight: 0.4, range: 9...18, notes: ["Бизнес-ланч", "Столовая", ""]),
            Leaf(subcategory: "Кофе", weight: 0.35, range: 4...9, notes: ["Капучино", "Раф", ""]),
            Leaf(subcategory: "Доставка", weight: 0.1, range: 25...60, notes: ["Пицца", "Суши"]),
            Leaf(subcategory: nil, weight: 0.15, range: 30...90, notes: ["Ужин с друзьями", ""])
        ]),
        "Транспорт": Profile(dailyChance: 0.55, range: 1...12, leaves: [
            Leaf(subcategory: "Такси", weight: 0.25, range: 6...18, notes: ["", "В аэропорт"]),
            Leaf(subcategory: "Метро", weight: 0.6, range: 0.9...1.2),
            Leaf(subcategory: nil, weight: 0.15, range: 1...3, notes: ["Самокат", ""])
        ]),
        "Дом": Profile(monthlyDay: 5, range: 150...240, leaves: [Leaf(subcategory: nil, weight: 1, notes: ["Коммуналка"])]),
        "Связь": Profile(monthlyDay: 12, range: 25...32, leaves: [Leaf(subcategory: nil, weight: 1, notes: ["Интернет и мобильный"])]),
        "Здоровье": Profile(dailyChance: 0.06, range: 8...90, leaves: [
            Leaf(subcategory: "Аптека", weight: 0.7, range: 8...40, notes: ["", "Витамины"]),
            Leaf(subcategory: nil, weight: 0.3, notes: ["Стоматолог", "Анализы"])
        ]),
        "Развлечения": Profile(dailyChance: 0.1, range: 12...60, leaves: [
            Leaf(subcategory: nil, weight: 1, notes: ["Кино", "Боулинг", "Концерт", ""])
        ]),
        "Одежда": Profile(dailyChance: 0.04, range: 40...220, leaves: [
            Leaf(subcategory: nil, weight: 1, notes: ["Кроссовки", "Куртка", ""])
        ]),
        "Подписки": Profile(monthlyDay: 20, range: 9...20, leaves: [Leaf(subcategory: nil, weight: 1, notes: ["Музыка", "Облако"])]),
        "Подарки": Profile(dailyChance: 0.03, range: 25...120, leaves: [
            Leaf(subcategory: "Друзья", weight: 0.6, notes: ["", "На день рождения"]),
            Leaf(subcategory: nil, weight: 0.4)
        ]),
        "Образование": Profile(dailyChance: 0.03, range: 15...90, leaves: [
            Leaf(subcategory: nil, weight: 1, notes: ["Книги", "Курс"])
        ]),
        "Другое": Profile(dailyChance: 0.08, range: 3...35, leaves: [
            Leaf(subcategory: nil, weight: 1, notes: ["", "Химчистка"])
        ])
    ]
    private static let fallbackProfile = Profile(dailyChance: 0.08, range: 5...50, leaves: [Leaf(subcategory: nil, weight: 1)])

    /// Траты без категории: день назад от сегодня, сумма в копейках, заметка.
    private static let uncategorized: [(daysAgo: Int, amountMinor: Int64, note: String)] = [
        (3, 1_240, "Сувенир"),
        (17, 700, ""),
        (41, 2_550, "Подарок коллеге")
    ]

    /// Зерно генератора: одинаковые данные при каждом заполнении в один день.
    private static let seed: UInt64 = 2026

    /// Добавляет подкатегории базовым категориям (если их нет) и траты за последние `days` дней
    /// по активным категориям к текущим данным.
    static func fill(context: ModelContext, currencyCode: String, days: Int = 92) throws {
        let store = ExpenseStore(context: context)
        try addSubcategories(store: store)
        let payload = try makePayload(store: store, currencyCode: currencyCode, days: days)
        try BackupImporter.apply(payload, to: context, mode: .merge)
    }

    /// Удаляет все категории и траты и заново создаёт базовые категории — как после установки.
    static func eraseAll(context: ModelContext, defaults: UserDefaults = .standard) throws {
        let empty = BackupPayload(
            exportedAt: .now,
            currencyCode: CurrencySettings.currencyCode(in: defaults),
            categories: [],
            expenses: []
        )
        try BackupImporter.apply(empty, to: context, mode: .replace)
        defaults.removeObject(forKey: SettingsKeys.didSeedDefaultCategories)
        try ExpenseStore(context: context).seedDefaultCategoriesIfNeeded(defaults: defaults, names: DefaultCategories.localizedNames)
    }

    private static func addSubcategories(store: ExpenseStore) throws {
        for parent in try store.topLevelCategories() {
            let existing = Set(store.subcategories(of: parent, includingArchived: true).map(\.name))
            for template in subcategories[templateName(parent)] ?? [] where !existing.contains(text(template.name)) {
                try store.addSubcategory(name: text(template.name), iconName: template.icon, parent: parent)
            }
        }
    }

    private static func makePayload(
        store: ExpenseStore,
        currencyCode: String,
        days: Int,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> BackupPayload {
        var random = SeededGenerator(seed: seed)
        let targets = try store.topLevelCategories().map { parent in
            (parent: parent, children: store.subcategories(of: parent), profile: profiles[templateName(parent)] ?? fallbackProfile)
        }
        let today = calendar.startOfDay(for: now)
        var expenses: [BackupPayload.ExpenseRecord] = []

        func record(day: Date, amount: Double, note: String, categoryID: UUID?) {
            guard let amountMinor = Money.minor(fromMajor: Decimal(amount)), amountMinor > 0 else { return }
            // С 8:00 до 22:00, но не позже текущего момента.
            let date = min(day.addingTimeInterval(.random(in: 8 * 3600...22 * 3600, using: &random)), now)
            expenses.append(BackupPayload.ExpenseRecord(
                id: UUID(), amountMinor: amountMinor, date: date, note: note,
                categoryID: categoryID, createdAt: date, updatedAt: date
            ))
        }

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let weekendFactor = calendar.isDateInWeekend(day) ? 1.5 : 1
            let dayOfMonth = calendar.component(.day, from: day)

            for target in targets {
                let profile = target.profile
                let roll = Double.random(in: 0..<1, using: &random)
                let happens = profile.monthlyDay.map { $0 == dayOfMonth } ?? (roll < profile.dailyChance * weekendFactor)
                guard happens, let leaf = pickLeaf(profile.leaves, using: &random) else { continue }
                let leafID = leaf.subcategory.flatMap { name in target.children.first { $0.name == text(name) }?.id }
                record(
                    day: day,
                    amount: Double.random(in: leaf.range ?? profile.range, using: &random),
                    note: text(leaf.notes.randomElement(using: &random) ?? ""),
                    categoryID: leafID ?? target.parent.id
                )
            }
        }
        for item in uncategorized where item.daysAgo < days {
            guard let day = calendar.date(byAdding: .day, value: -item.daysAgo, to: today) else { continue }
            record(day: day, amount: Double(item.amountMinor) / 100, note: text(item.note), categoryID: nil)
        }
        return BackupPayload(exportedAt: now, currencyCode: currencyCode, categories: [], expenses: expenses)
    }

    /// Русское имя шаблона базовой категории — ключ таблиц выше; на английском базовые категории
    /// создаются с именами из каталога (`DefaultCategories.localizedNames`).
    private static func templateName(_ parent: ExpenseCategory) -> String {
        guard let index = DefaultCategories.localizedNames.firstIndex(of: parent.name) else { return parent.name }
        return DefaultCategories.all[index].name
    }

    /// Имена подкатегорий и заметки демо-данных на языке интерфейса — для скриншотов английской версии.
    private static func text(_ russian: String) -> String {
        AppLanguage.current == .english ? english[russian] ?? russian : russian
    }

    private static let english: [String: String] = [
        "Супермаркет": "Supermarket", "Рынок": "Market", "Хлеб и выпечка": "Bread & Pastries",
        "Обеды": "Lunches", "Кофе": "Coffee", "Доставка": "Delivery", "Такси": "Taxi", "Метро": "Metro",
        "Аптека": "Pharmacy", "Друзья": "Friends",
        "Евроопт": "Evroopt", "Гиппо": "Hippo", "Корона": "Korona", "Комаровка": "Komarovka",
        "Овощи и фрукты": "Fruit & vegetables", "Круассаны": "Croissants", "Вода": "Water", "Молоко": "Milk",
        "Бизнес-ланч": "Business lunch", "Столовая": "Canteen", "Капучино": "Cappuccino", "Раф": "Raf coffee",
        "Пицца": "Pizza", "Суши": "Sushi", "Ужин с друзьями": "Dinner with friends", "В аэропорт": "To the airport",
        "Самокат": "Scooter", "Коммуналка": "Utilities", "Интернет и мобильный": "Internet & mobile",
        "Витамины": "Vitamins", "Стоматолог": "Dentist", "Анализы": "Lab tests", "Кино": "Movies",
        "Боулинг": "Bowling", "Концерт": "Concert", "Кроссовки": "Sneakers", "Куртка": "Jacket", "Музыка": "Music",
        "Облако": "Cloud storage", "На день рождения": "Birthday present", "Книги": "Books", "Курс": "Online course",
        "Химчистка": "Dry cleaning", "Сувенир": "Souvenir", "Подарок коллеге": "Gift for a colleague"
    ]

    private static func pickLeaf(_ leaves: [Leaf], using random: inout SeededGenerator) -> Leaf? {
        let total = leaves.reduce(0) { $0 + $1.weight }
        var point = Double.random(in: 0..<max(total, .leastNonzeroMagnitude), using: &random)
        for leaf in leaves {
            if point < leaf.weight { return leaf }
            point -= leaf.weight
        }
        return leaves.last
    }
}

/// SplitMix64: простой генератор с зерном — повторяемые демо-данные.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Группа настроек для проверки: демо-данные и полная очистка (`debug.*`).
struct DebugDataSection: View {
    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingErase = false
    @State private var alert: FailureAlert?

    var body: some View {
        SettingsGroup(header: "debug.header", footer: "debug.footer") {
            Button {
                perform { try DemoData.fill(context: modelContext, currencyCode: currencyCode) }
            } label: {
                SettingsRow("debug.fill")
            }
            Button {
                isConfirmingErase = true
            } label: {
                Text("debug.erase")
                    .typeStyle(.body)
                    .foregroundStyle(Theme.destructive)
                    .frame(maxWidth: .infinity, minHeight: SettingsLayout.rowHeight, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .contentShape(Rectangle())
            }
            .confirmationDialog("debug.eraseConfirm", isPresented: $isConfirmingErase, titleVisibility: .visible) {
                Button("debug.eraseConfirmButton", role: .destructive) {
                    perform { try DemoData.eraseAll(context: modelContext) }
                }
            } message: {
                Text("debug.eraseConfirmMessage")
            }
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
        .failureAlert($alert)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            alert = .store(error)
        }
    }
}
#endif
