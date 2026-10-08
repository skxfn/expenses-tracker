import Foundation
import Observation
import ExpenseCore

/// Состояние формы категории: создание, редактирование, архив, удаление.
///
/// Флаги архива и число расходов копируются при открытии: после удаления категории
/// форма ещё перерисовывается, а читать свойства удалённой модели SwiftData небезопасно.
@Observable
final class CategoryFormModel {
    /// `nil` — новая категория.
    let category: ExpenseCategory?
    let categoryID: UUID?
    var name: String
    var iconName: String
    var colorHex: String
    var errorMessage: String?
    private(set) var isArchived: Bool
    let expenseCount: Int

    init(category: ExpenseCategory?) {
        self.category = category
        categoryID = category?.id
        name = category?.name ?? ""
        iconName = category?.iconName ?? "tag.fill"
        colorHex = category?.colorHex ?? CategoryPalette.colors.first ?? CategoryAppearance.uncategorized.colorHex
        isArchived = category?.isArchived ?? false
        expenseCount = category?.expenses.count ?? 0
    }

    var isEditing: Bool { category != nil }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Для превью: пока имя пустое, показываем подсказку.
    var appearance: CategoryAppearance {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return CategoryAppearance(name: trimmed.isEmpty ? "Название" : trimmed, iconName: iconName, colorHex: colorHex)
    }

    /// `true` — сохранено, форму можно закрыть.
    func save(using store: ExpenseStore) -> Bool {
        perform {
            if let category {
                try store.updateCategory(category, name: name, iconName: iconName, colorHex: colorHex)
            } else {
                try store.addCategory(name: name, iconName: iconName, colorHex: colorHex)
            }
        }
    }

    func toggleArchive(using store: ExpenseStore) {
        guard let category else { return }
        let succeeded = perform {
            if isArchived {
                try store.unarchiveCategory(category)
            } else {
                try store.archiveCategory(category)
            }
        }
        if succeeded { isArchived.toggle() }
    }

    /// Удаляет категорию; её расходы переносятся в `target` или остаются без категории.
    /// `true` — удалено.
    func delete(using store: ExpenseStore, reassignTo target: ExpenseCategory?) -> Bool {
        guard let category else { return false }
        return perform { try store.deleteCategory(category, reassignTo: target) }
    }

    private func perform(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
