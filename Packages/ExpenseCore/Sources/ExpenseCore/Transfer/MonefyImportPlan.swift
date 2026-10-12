import Foundation

/// Куда записать траты одной категории Monefy. Категории Monefy в приложении не создаются.
public enum MonefyCategoryTarget: Hashable, Sendable {
    /// Категория или подкатегория приложения.
    case category(UUID)
    /// «Без категории».
    case uncategorized
    /// «Не переносить»: траты этой категории не импортируются.
    case skip

    /// Значение для UserDefaults (запомненное сопоставление): `uuid`, `uncategorized` или `skip`.
    public var storageValue: String {
        switch self {
        case .category(let id): id.uuidString
        case .uncategorized: "uncategorized"
        case .skip: "skip"
        }
    }

    public init?(storageValue: String) {
        switch storageValue {
        case "uncategorized": self = .uncategorized
        case "skip": self = .skip
        default:
            guard let id = UUID(uuidString: storageValue) else { return nil }
            self = .category(id)
        }
    }
}

/// Что лежит в файле Monefy: траты по категориям Monefy — для экрана сопоставления до импорта.
public struct MonefyImportPlan: Equatable, Sendable {
    /// Категория Monefy и её траты в файле.
    public struct Group: Identifiable, Equatable, Sendable {
        /// Имя категории Monefy — ключ сопоставления.
        public let name: String
        public fileprivate(set) var expenseCount = 0
        /// Сумма трат в сотых долях (при переполнении — `Int64.max`).
        public fileprivate(set) var totalMinor: Int64 = 0

        public var id: String { name }
    }

    public let file: MonefyCSV.File
    /// Категории Monefy: больше сумма — выше (как списки категорий в приложении), при равенстве — по имени.
    public let groups: [Group]
    /// Первый и последний день трат; `nil` — трат нет.
    public let period: ClosedRange<MonefyCSV.Day>?

    public init(file: MonefyCSV.File) {
        self.file = file
        var groups: [String: Group] = [:]
        for expense in file.expenses {
            var group = groups[expense.category] ?? Group(name: expense.category)
            group.expenseCount += 1
            let (total, overflow) = group.totalMinor.addingReportingOverflow(expense.amountMinor)
            group.totalMinor = overflow ? .max : total
            groups[expense.category] = group
        }
        self.groups = groups.values.sorted { lhs, rhs in
            lhs.totalMinor != rhs.totalMinor ? lhs.totalMinor > rhs.totalMinor : lhs.name < rhs.name
        }
        let days = file.expenses.map(\.day)
        if let first = days.min(), let last = days.max() {
            period = first...last
        } else {
            period = nil
        }
    }

    /// Траты файла.
    public var expenseCount: Int { file.expenses.count }

    /// Строки файла, которые не траты: доходы, переводы и начальные остатки.
    public var notExpenseCount: Int { file.incomeCount + file.transferCount }

    /// Категории Monefy, для которых ещё ничего не выбрано.
    public func unmappedCount(_ mapping: [String: MonefyCategoryTarget]) -> Int {
        groups.count { mapping[$0.name] == nil }
    }

    /// Сколько трат пойдёт в импорт при этом сопоставлении (без «Не переносить», до проверки повторов).
    public func importCount(_ mapping: [String: MonefyCategoryTarget]) -> Int {
        groups.filter { mapping[$0.name].map { $0 != .skip } ?? false }.reduce(0) { $0 + $1.expenseCount }
    }

    /// Запомненное сопоставление для этого файла: только его категории Monefy и только существующие
    /// категории приложения (`categoryIDs`) — удалённая с прошлого раза категория снова ждёт выбора.
    public func restoredMapping(_ stored: [String: String], categoryIDs: Set<UUID>) -> [String: MonefyCategoryTarget] {
        var mapping: [String: MonefyCategoryTarget] = [:]
        for group in groups {
            guard let target = stored[group.name].flatMap(MonefyCategoryTarget.init(storageValue:)) else { continue }
            if case .category(let id) = target, !categoryIDs.contains(id) { continue }
            mapping[group.name] = target
        }
        return mapping
    }
}
