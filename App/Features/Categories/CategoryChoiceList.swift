import SwiftData
import SwiftUI
import ExpenseCore

/// Выбор категории списком в стиле настроек: родитель подкатегории в редакторе и «Перенести траты…»
/// при удалении. Категории — плашкой tint, подкатегории — с отступом, плашкой своей ступени.
struct CategoryChoiceList: View {
    /// Категории верхнего уровня по порядку.
    let groups: [ExpenseCategory]
    /// Показывать активные подкатегории под категорией.
    var includesSubcategories = false
    /// Подкатегории, которых нет в списке (удаляемая).
    var excludedIDs: Set<UUID> = []
    var selectedID: UUID?
    let onSelect: (ExpenseCategory) -> Void

    var body: some View {
        ScrollView {
            SettingsGroup {
                ForEach(groups) { group in
                    let tone = GouacheTone(mainHex: group.colorHex)
                    row(group, isSubcategory: false) {
                        CategoryPlaque(iconName: group.iconName, tone: tone)
                    }
                    if includesSubcategories {
                        let siblings = SubcategoryShades.ordered(group.children)
                        ForEach(Array(siblings.enumerated()), id: \.element.id) { index, subcategory in
                            if !subcategory.isArchived, !excludedIDs.contains(subcategory.id) {
                                let step = SubcategoryShades.step(forPosition: index)
                                row(subcategory, isSubcategory: true) {
                                    MiniPlaque(
                                        iconName: subcategory.iconName,
                                        fill: (tone ?? .grafit).shade(step),
                                        iconColor: (tone ?? .grafit).labelOnShade(step),
                                        side: CategoryChoiceList.subPlaque
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background(Theme.canvasElevated)
        .sensoryFeedback(Haptic.selection, trigger: selectedID)
    }

    /// Плашка подкатегории — меньше плашки категории.
    static let subPlaque: CGFloat = 28

    private func row(_ category: ExpenseCategory, isSubcategory: Bool, @ViewBuilder plaque: () -> some View) -> some View {
        let isSelected = category.id == selectedID
        return Button {
            onSelect(category)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                plaque()
                    .frame(width: Theme.Size.plaque)
                Text(verbatim: category.name)
                    .typeStyle(.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if isSelected {
                    Image(systemName: "checkmark")
                        .typeStyle(.headline)
                        .foregroundStyle(Theme.ink)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, isSubcategory ? Theme.Size.plaque + Theme.Spacing.md : 0)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(minHeight: SettingsLayout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Родитель подкатегории (пуш внутри шита редактора, `cat.groupPicker.title`).
struct CategoryParentPicker: View {
    let candidates: [ExpenseCategory]
    @Binding var selection: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CategoryChoiceList(groups: candidates, selectedID: selection) { category in
            selection = category.id
            dismiss()
        }
        .navigationTitle("cat.groupPicker.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// «Перенести траты…» при удалении (шит со списком, `catDelete.pickerLabel`): активные категории
/// и подкатегории, кроме удаляемой и её подкатегорий.
struct CategoryReassignSheet: View {
    /// Удаляемая категория (её подкатегории тоже исключаются).
    let excludedID: UUID?
    let onPick: (ExpenseCategory) -> Void

    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder), SortDescriptor(\ExpenseCategory.createdAt)])
    private var categories: [ExpenseCategory]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CategoryChoiceList(groups: targets, includesSubcategories: true, excludedIDs: excludedID.map { [$0] } ?? []) { category in
                onPick(category)
            }
            .sheetHeader("catDelete.pickerLabel", onClose: { dismiss() })
        }
    }

    /// Категории верхнего уровня, кроме удаляемой (вместе с ней уходят и её подкатегории).
    private var targets: [ExpenseCategory] {
        categories.filter { $0.parent == nil && !$0.isArchived && $0.id != excludedID }
    }
}
