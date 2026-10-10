import Foundation
import Observation
import SwiftUI
import ExpenseCore

/// Уровень категории в редакторе: сегмент «Категория / Подкатегория».
enum CategoryKind: Hashable {
    /// Категория верхнего уровня: свой тон «Гуаши».
    case group
    /// Подкатегория: цвет — ступень тона родителя.
    case subcategory
}

/// Что открыть в редакторе категории (`CategoryEditorSheet`).
enum CategoryEditorMode: Hashable, Identifiable {
    /// Новая категория. `name` — предзаполненное имя («Создать «…»» из поиска во «Все категории»);
    /// `parentID` — родитель новой подкатегории. Без родителя — категория верхнего уровня,
    /// а если их уже 15 — подкатегория первой категории.
    case create(name: String = "", parentID: UUID? = nil)
    /// Правка существующей категории или подкатегории.
    case edit(categoryID: UUID)

    var id: String {
        switch self {
        case .create(let name, let parentID): "create-\(parentID?.uuidString ?? "top")-\(name)"
        case .edit(let categoryID): "edit-\(categoryID.uuidString)"
        }
    }
}

/// Лесенка оттенков подкатегории: имена сестёр по ступеням и ступень редактируемой.
struct ShadeLadderState: Equatable {
    let tone: GouacheTone
    /// Имена сестёр на каждой из `SubcategoryShades.stepCount` ступеней (у шестой и дальше — повтор).
    let names: [[String]]
    /// Ступень этой подкатегории.
    let currentStep: Int
    /// Сестёр вместе с этой больше, чем ступеней: оттенки повторяются (`cat.shades.overflow`).
    let overflows: Bool
}

/// Состояние редактора категории: создание и правка, смена уровня, архив, удаление.
///
/// Флаги, имена и числа копируются при открытии: после удаления категории шит ещё перерисовывается,
/// а читать свойства удалённой модели SwiftData нельзя (ловушка AGENTS.md). Список категорий
/// загружается один раз (и после архивации): пока шит открыт, менять их может только он.
@Observable
final class CategoryFormModel {
    let mode: CategoryEditorMode
    /// Редактируемая категория; `nil` — новая или уже удалена.
    private(set) var category: ExpenseCategory?
    /// Копия `id` редактируемой категории: после удаления модель читать нельзя.
    let categoryID: UUID?
    /// Категория удалена — экран больше ничего не читает и закрывается.
    private(set) var isDeleted = false

    var name: String {
        didSet {
            if name.count > Self.nameLimit { name = String(name.prefix(Self.nameLimit)) }
            if name != oldValue { isDuplicateName = false }
        }
    }
    var iconName: String
    /// Тон категории верхнего уровня (у подкатегории — тон родителя, только для показа).
    var tone: GouacheTone
    var kind: CategoryKind {
        didSet { if kind != oldValue { kindChanged() } }
    }
    var parentID: UUID?
    var alert: FailureAlert?
    /// Имя занято — строка `cat.name.duplicate` под полем.
    private(set) var isDuplicateName = false
    private(set) var isArchived: Bool

    // Снимок при открытии.
    let originalKind: CategoryKind
    let originalName: String
    /// Имя родителя подкатегории при открытии — для текста удаления.
    let originalParentName: String?
    /// Траты категории, а у категории верхнего уровня — вместе с тратами подкатегорий.
    let expenseCount: Int
    let subcategoryCount: Int

    // Список категорий на время шита.
    private(set) var topLevel: [ExpenseCategory] = []
    private(set) var occupiedTones: [GouacheTone: String] = [:]
    private(set) var isLimitReached = false

    private let store: ExpenseStore

    /// Длина названия (`cat.name.label`: maxlength 24).
    static let nameLimit = 24
    /// Иконка новой категории верхнего уровня, пока не выбрана другая («Три точки»).
    static let defaultIconName = "more-3-fill"

    init(mode: CategoryEditorMode, store: ExpenseStore) {
        self.mode = mode
        self.store = store
        let topLevel = (try? store.topLevelCategories()) ?? []
        let limitReached = (try? store.isTopLevelLimitReached()) ?? false

        switch mode {
        case .edit(let id):
            let category = (try? store.allCategories())?.first { $0.id == id }
            let children = category?.children ?? []
            self.category = category
            categoryID = category?.id
            originalParentName = category?.parent?.name
            let kind: CategoryKind = category?.parent == nil ? .group : .subcategory
            name = category?.name ?? ""
            originalName = category?.name ?? ""
            iconName = category?.iconName ?? Self.defaultIconName
            tone = (category?.parent ?? category).flatMap { GouacheTone(mainHex: $0.colorHex) } ?? .grafit
            self.kind = kind
            originalKind = kind
            parentID = category?.parent?.id
            isArchived = category?.isArchived ?? false
            subcategoryCount = children.count
            expenseCount = (category?.expenses.count ?? 0) + children.reduce(0) { $0 + $1.expenses.count }
        case .create(let name, let requestedParentID):
            let parent = requestedParentID.flatMap { id in topLevel.first { $0.id == id } }
                ?? (limitReached ? topLevel.first : nil)
            category = nil
            categoryID = nil
            originalParentName = nil
            let kind: CategoryKind = parent == nil ? .group : .subcategory
            self.name = String(name.prefix(Self.nameLimit))
            originalName = ""
            iconName = parent?.iconName ?? Self.defaultIconName
            tone = parent.flatMap { GouacheTone(mainHex: $0.colorHex) } ?? .grafit
            self.kind = kind
            originalKind = kind
            parentID = parent?.id
            isArchived = false
            subcategoryCount = 0
            expenseCount = 0
        }
        reload()
        if mode.isCreate, kind == .group, let free = firstFreeTone { tone = free }
    }

    // MARK: - Состояние для экрана

    var isEditing: Bool { categoryID != nil }

    var title: LocalizedStringKey {
        switch (isEditing, kind) {
        case (false, .group): "cat.title.newGroup"
        case (false, .subcategory): "cat.title.new"
        case (true, .group): "cat.title.edit.group"
        case (true, .subcategory): "cat.title.edit.sub"
        }
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// «Готово» активна: есть название, у подкатегории выбран родитель.
    var canSave: Bool {
        !trimmedName.isEmpty && (kind == .group || parent != nil)
    }

    /// Пункт «Категория» неактивен: категорий уже 15 (`cat.group.limit`). Правке категории верхнего
    /// уровня и архивной подкатегории лимит не мешает.
    var isGroupBlocked: Bool {
        guard originalKind == .subcategory || !isEditing else { return false }
        return isLimitReached && !isArchived
    }

    /// Пункт «Подкатегория» неактивен: у категории есть подкатегории (`cat.typeSwitch.block`) или некуда вложить.
    var isSubcategoryBlocked: Bool {
        (isEditing && originalKind == .group && subcategoryCount > 0) || parentCandidates.isEmpty
    }

    /// Сноска под сегментом: почему другой пункт неактивен.
    var kindFootnote: LocalizedStringKey? {
        if kind == .subcategory, isGroupBlocked { return "cat.group.limit" }
        if kind == .group, isEditing, subcategoryCount > 0 { return "cat.typeSwitch.block" }
        return nil
    }

    /// Куда можно вложить: активные категории верхнего уровня, кроме самой себя.
    var parentCandidates: [ExpenseCategory] {
        topLevel.filter { $0.id != categoryID }
    }

    /// Выбранный родитель (может быть архивным, если такой был у подкатегории при открытии).
    var parent: ExpenseCategory? {
        guard let parentID else { return nil }
        return topLevel.first { $0.id == parentID } ?? (category?.parent?.id == parentID ? category?.parent : nil)
    }

    /// Тон родителя подкатегории.
    var parentTone: GouacheTone {
        parent.flatMap { GouacheTone(mainHex: $0.colorHex) } ?? .grafit
    }

    /// Лесенка оттенков родителя; `nil` — не подкатегория или родитель не выбран.
    /// Порядок — по созданию, архивные держат место; новая и перенесённая встают в конец.
    var ladder: ShadeLadderState? {
        guard kind == .subcategory, let parent else { return nil }
        let siblings = SubcategoryShades.ordered(parent.children)
        var names = Array(repeating: [String](), count: SubcategoryShades.stepCount)
        for (index, sibling) in siblings.enumerated() where sibling.id != categoryID {
            names[SubcategoryShades.step(forPosition: index)].append(sibling.name)
        }
        let position = siblings.firstIndex { $0.id == categoryID } ?? siblings.count
        let total = siblings.contains { $0.id == categoryID } ? siblings.count : siblings.count + 1
        return ShadeLadderState(
            tone: parentTone,
            names: names,
            currentStep: SubcategoryShades.step(forPosition: position),
            overflows: total > SubcategoryShades.stepCount
        )
    }

    // MARK: - Действия

    /// Сохраняет; `id` категории — сохранено, шит можно закрыть. Занятое имя — строка под полем.
    func save() -> UUID? {
        do {
            switch (category, kind) {
            case (nil, .group):
                return try store.addCategory(name: name, iconName: iconName, colorHex: tone.mainHex).id
            case (nil, .subcategory):
                guard let parent else { return nil }
                return try store.addSubcategory(name: name, iconName: iconName, parent: parent).id
            case (let category?, .group):
                try store.updateCategory(category, name: name, iconName: iconName, colorHex: tone.mainHex, parent: nil)
                return category.id
            case (let category?, .subcategory):
                guard let parent else { return nil }
                try store.updateCategory(category, name: name, iconName: iconName, colorHex: parent.colorHex, parent: parent)
                return category.id
            }
        } catch ExpenseStoreError.duplicateCategoryName {
            isDuplicateName = true
        } catch {
            alert = .store(error)
        }
        return nil
    }

    func toggleArchive() {
        guard let category else { return }
        do {
            if isArchived {
                try store.unarchiveCategory(category)
            } else {
                try store.archiveCategory(category)
            }
            isArchived.toggle()
            reload()
        } catch {
            alert = .store(error)
        }
    }

    /// Куда по умолчанию уходят траты при удалении: у подкатегории — в родителя «без подкатегории»,
    /// у категории — «без категории».
    var defaultReassignTarget: ExpenseCategory? {
        originalKind == .subcategory ? category?.parent : nil
    }

    /// Удаляет; траты — в `target` (`nil` — без категории). `true` — удалено.
    func delete(reassignTo target: ExpenseCategory?) -> Bool {
        guard let category else { return false }
        do {
            try store.deleteCategory(category, reassignTo: target)
            self.category = nil
            isDeleted = true
            return true
        } catch {
            alert = .store(error)
            return false
        }
    }

    // MARK: - Внутреннее

    private func reload() {
        topLevel = (try? store.topLevelCategories()) ?? []
        occupiedTones = (try? store.occupiedTones(excluding: category)) ?? [:]
        isLimitReached = (try? store.isTopLevelLimitReached()) ?? false
    }

    /// Первый свободный тон по оттенку.
    private var firstFreeTone: GouacheTone? {
        GouacheTone.allCases.first { occupiedTones[$0] == nil }
    }

    /// Смена уровня: подкатегории — родитель (первый подходящий), категории — свободный тон вместо занятого.
    private func kindChanged() {
        switch kind {
        case .subcategory:
            if parent == nil { parentID = parentCandidates.first?.id }
        case .group:
            if occupiedTones[tone] != nil, let free = firstFreeTone { tone = free }
        }
    }
}

private extension CategoryEditorMode {
    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }
}
