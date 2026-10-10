import SwiftData
import SwiftUI
import ExpenseCore

/// Категория с подкатегориями для «Всех категорий».
struct PickerGroup: Identifiable {
    struct Subcategory: Identifiable {
        let choice: CategoryChoice
        /// Ступень оттенка: позиция среди сестёр по созданию (архивные держат место).
        let step: Int
        var id: UUID { choice.id }
    }

    let choice: CategoryChoice
    let subcategories: [Subcategory]
    var id: UUID { choice.id }

    /// Категории верхнего уровня в пользовательском порядке. Архивные не показываются, кроме категории
    /// правимой траты (`keepingID`) и её родителя (`picker.archived`). Поиск — по именам без учёта регистра:
    /// совпало имя категории — видны все её подкатегории, иначе только совпавшие.
    static func make(from categories: [ExpenseCategory], keepingID keepID: UUID?, query: String) -> [PickerGroup] {
        let keptParentID = categories.first { $0.id == keepID }?.parent?.id
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)

        func isVisible(_ category: ExpenseCategory) -> Bool {
            !category.isArchived || category.id == keepID || category.id == keptParentID
        }
        func matches(_ category: ExpenseCategory) -> Bool {
            needle.isEmpty || category.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }

        return categories.compactMap { group in
            guard group.parent == nil, isVisible(group) else { return nil }
            let subcategories = SubcategoryShades.ordered(group.children).enumerated().compactMap { position, sub -> Subcategory? in
                // У архивной категории — только подкатегория правимой траты.
                let isShown = group.isArchived ? sub.id == keepID : isVisible(sub)
                guard isShown, matches(group) || matches(sub) else { return nil }
                return Subcategory(choice: CategoryChoice(sub), step: SubcategoryShades.step(forPosition: position))
            }
            guard matches(group) || !subcategories.isEmpty else { return nil }
            return PickerGroup(choice: CategoryChoice(group), subcategories: subcategories)
        }
    }
}

/// Шит «Все категории» поверх шита записи (макет `07-picker`): поиск, категории с чипами подкатегорий,
/// плавающая «+ Новая категория». Выбор сразу закрывает шит.
struct CategoryPickerSheet: View {
    let selectedID: UUID?
    /// Категория правимой траты — видна, даже если в архиве.
    let keepingID: UUID?
    let auraTones: [GouacheTone]
    let onSelect: (CategoryChoice) -> Void
    /// Создать категорию (с текстом поиска для «Создать «…»»). Редактор подключает этап «Категории».
    let onCreateCategory: (String) -> Void

    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder), SortDescriptor(\ExpenseCategory.createdAt)])
    private var categories: [ExpenseCategory]

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    /// Шит выглядывает из-под шита записи сверху, как в макете; тянется до полного.
    private static let detent = PresentationDetent.fraction(0.75)

    var body: some View {
        let groups = PickerGroup.make(from: categories, keepingID: keepingID, query: query)
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    searchField
                        .padding(.bottom, Theme.Spacing.xs)
                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups) { group in
                            PickerRow(group: group, selectedID: selectedID, onSelect: onSelect)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.immediately)
            .sheetHeader("picker.title", onClose: { dismiss() })
            .safeAreaInset(edge: .bottom, spacing: 0) { newCategoryButton }
        }
        .presentationDetents([Self.detent, .large])
        .presentationBackground {
            AuraBackground(tones: auraTones, base: Theme.canvasElevated)
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            TextField(text: $query, prompt: Text("picker.search.placeholder").foregroundStyle(Theme.placeholder)) {
                Text("picker.search.a11y")
            }
            .typeStyle(.body)
            .foregroundStyle(Theme.ink)
            .tint(Theme.ink)
            .autocorrectionDisabled()
            .submitLabel(.search)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(minHeight: Theme.Size.chip)
        .glass(.inContent)
    }

    @ViewBuilder
    private var emptyState: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if trimmed.isEmpty {
                Text("picker.noCategories.title")
                    .typeStyle(.headline)
                    .foregroundStyle(Theme.ink)
                Text("picker.noCategories.body")
                    .typeStyle(.subheadline)
                    .foregroundStyle(Theme.secondary)
            } else {
                Text("picker.searchEmpty.title")
                    .typeStyle(.headline)
                    .foregroundStyle(Theme.ink)
                Button {
                    onCreateCategory(trimmed)
                } label: {
                    Text(verbatim: L10n.format("picker.searchEmpty.create", trimmed))
                }
                .buttonStyle(.glassCapsule(height: Theme.Size.chip, expands: false))
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.md)
    }

    private var newCategoryButton: some View {
        Button {
            onCreateCategory("")
        } label: {
            Label("picker.new", systemImage: "plus")
        }
        .buttonStyle(.glassCapsule(expands: false))
        .padding(.bottom, Theme.Spacing.sm)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// Строка категории: tint-плашка 44 и имя (выбор категории «без подкатегории»), чипы подкатегорий оттенками.
/// Выбранное обведено графитом.
private struct PickerRow: View {
    let group: PickerGroup
    let selectedID: UUID?
    let onSelect: (CategoryChoice) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
        let isGroupSelected = group.choice.id == selectedID
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Button { onSelect(group.choice) } label: {
                PickerPlaque(choice: group.choice)
                    .overlay {
                        if isGroupSelected { SelectionRing(cornerRadius: Theme.Radius.plaque) }
                    }
            }
            .buttonStyle(.pressable(Motion.PressScale.circle))
            .accessibilityHidden(true)

            FlowLayout {
                Button { onSelect(group.choice) } label: {
                    Text(verbatim: group.choice.name)
                        .typeStyle(.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .frame(minHeight: Theme.Size.chip)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: groupAccessibilityName))
                .accessibilityAddTraits(isGroupSelected ? .isSelected : [])

                if group.choice.isArchived {
                    archivedBadge
                }
                ForEach(group.subcategories) { sub in
                    chip(sub)
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: shape)
        .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
    }

    /// «Продукты, без подкатегории» — если подкатегории есть; иначе просто имя.
    private var groupAccessibilityName: String {
        group.subcategories.isEmpty && !group.choice.hasSubcategories
            ? group.choice.name
            : L10n.format("picker.group.a11y", group.choice.name)
    }

    private var archivedBadge: some View {
        Text("picker.archived")
            .typeStyle(.footnote)
            .foregroundStyle(Theme.secondary)
            .frame(minHeight: Theme.Size.chip)
    }

    private func chip(_ sub: PickerGroup.Subcategory) -> some View {
        let isSelected = sub.id == selectedID
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
        let tone = group.choice.tone
        return Button { onSelect(sub.choice) } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(verbatim: sub.choice.name)
                    .lineLimit(1)
                if sub.choice.isArchived && !group.choice.isArchived {
                    Text("picker.archived")
                        .typeStyle(.footnote)
                }
            }
            .typeStyle(.callout)
            .foregroundStyle(tone?.labelOnShade(sub.step) ?? CategoryPaint.onArea(nil))
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: Theme.Size.chip)
            .background(tone?.shade(sub.step) ?? CategoryPaint.area(nil), in: shape)
            .overlay {
                if isSelected { SelectionRing(cornerRadius: Theme.Radius.swatch) }
            }
        }
        .buttonStyle(.pressable())
        .accessibilityLabel(Text(verbatim: sub.choice.accessibilityName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Плашка категории 44 (цель касания) во «Всех категориях»: tint с deep-иконкой (§8 п. 6).
private struct PickerPlaque: View {
    let choice: CategoryChoice

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.plaque, style: .continuous)
            .fill(CategoryPaint.area(choice.tone))
            .frame(width: Theme.Size.chip * scale, height: Theme.Size.chip * scale)
            .overlay {
                CategoryIconImage(name: choice.iconName)
                    .frame(width: Theme.Size.swatchIcon * scale, height: Theme.Size.swatchIcon * scale)
                    .foregroundStyle(CategoryPaint.onArea(choice.tone))
            }
    }
}
