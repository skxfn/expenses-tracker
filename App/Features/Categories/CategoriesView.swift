import SwiftData
import SwiftUI
import ExpenseCore

/// «Категории» (Настройки → Категории, `categories.*`): в стиле настроек — Large Title, группы на бумаге.
/// Активные категории в порядке записи (перестановка — «Изменить» и перетаскивание), под каждой —
/// её подкатегории; архив — отдельной секцией. Создание и правка — `CategoryEditorSheet`.
struct CategoriesView: View {
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder), SortDescriptor(\ExpenseCategory.createdAt)])
    private var categories: [ExpenseCategory]

    @Environment(\.modelContext) private var modelContext
    @State private var editorMode: CategoryEditorMode?
    @State private var alert: FailureAlert?

    var body: some View {
        let active = categories.filter { $0.parent == nil && !$0.isArchived }
        // Архив: архивные категории и архивные подкатегории активных категорий.
        let archived = categories.filter { $0.isArchived && $0.parent?.isArchived != true }
        List {
            if !active.isEmpty {
                Section {
                    ForEach(active) { category in
                        CategoryListRow(category: category, showsArchivedSubcategories: false) { editorMode = .edit(categoryID: $0) }
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("categories.activeFooter")
                        .typeStyle(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { category in
                        CategoryListRow(category: category, showsArchivedSubcategories: true) { editorMode = .edit(categoryID: $0) }
                    }
                } header: {
                    Text("categories.archive")
                        .typeStyle(.callout)
                        .foregroundStyle(Theme.secondary)
                        .textCase(nil)
                } footer: {
                    Text("categories.archiveFooter")
                        .typeStyle(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .overlay {
            if categories.isEmpty {
                emptyState
            }
        }
        .navigationTitle("categories.title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !active.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("categories.add", systemImage: "plus") {
                    editorMode = .create()
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            CategoryEditorSheet(mode: mode)
        }
        .failureAlert($alert)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Text("categories.emptyTitle")
                .typeStyle(.headline)
                .foregroundStyle(Theme.ink)
        } description: {
            Text("categories.emptyBody")
                .typeStyle(.subheadline)
                .foregroundStyle(Theme.secondary)
        } actions: {
            Button("categories.add") {
                editorMode = .create()
            }
            .buttonStyle(.glassCapsule(height: Theme.Size.chip, expands: false))
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        do {
            try ExpenseStore(context: modelContext).moveCategories(fromOffsets: source, toOffset: destination)
        } catch {
            alert = .store(error)
        }
    }
}

/// Строка списка: категория (плашка tint, имя, шеврон) и под ней с отступом подкатегории
/// (плашка своей ступени). Подкатегория архивной категории или архивная — в той же строке архива.
private struct CategoryListRow: View {
    let category: ExpenseCategory
    /// В архиве — все подкатегории (в том числе архивные); у активной — только активные.
    let showsArchivedSubcategories: Bool
    let onEdit: (UUID) -> Void

    var body: some View {
        let tone = GouacheTone(mainHex: (category.parent ?? category).colorHex)
        VStack(spacing: 0) {
            button(for: category, subtitle: category.parent?.name) {
                if category.parent == nil {
                    CategoryPlaque(iconName: category.iconName, tone: tone)
                } else {
                    subPlaque(category, tone: tone)
                }
            }
            if category.parent == nil {
                let siblings = SubcategoryShades.ordered(category.children)
                ForEach(Array(siblings.enumerated()), id: \.element.id) { index, subcategory in
                    if showsArchivedSubcategories || !subcategory.isArchived {
                        button(for: subcategory, subtitle: nil) {
                            subPlaque(subcategory, tone: tone, step: SubcategoryShades.step(forPosition: index))
                        }
                        .padding(.leading, Theme.Size.plaque + Theme.Spacing.md)
                    }
                }
            }
        }
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.separator)
    }

    private func subPlaque(_ subcategory: ExpenseCategory, tone: GouacheTone?, step: Int? = nil) -> some View {
        let tone = tone ?? .grafit
        let step = step ?? SubcategoryShades.step(of: subcategory) ?? 0
        return MiniPlaque(
            iconName: subcategory.iconName,
            fill: tone.shade(step),
            iconColor: tone.labelOnShade(step),
            side: CategoryChoiceList.subPlaque
        )
        .frame(width: Theme.Size.plaque)
    }

    private func button(
        for category: ExpenseCategory,
        subtitle: String?,
        @ViewBuilder plaque: () -> some View
    ) -> some View {
        Button {
            onEdit(category.id)
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                plaque()
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: category.name)
                        .typeStyle(.body)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .typeStyle(.footnote)
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.right")
                    .typeStyle(.footnoteStrong)
                    .foregroundStyle(Theme.graphic)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: SettingsLayout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        CategoriesView()
    }
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
#endif
