import SwiftData
import SwiftUI
import ExpenseCore

/// Редактор категории (макет `11-category`, шит): ✕, заголовок, «Готово» prominent в шапке; сегмент
/// «Категория / Подкатегория», превью-«выкраска», название, родитель, цвет (лесенка оттенков или
/// 15 образцов «Гуаши»), иконки с поиском; при правке — архив и удаление.
///
/// Открывать шитом: `.sheet(item:) { CategoryEditorSheet(mode: $0) { id in … } }`.
/// `onSaved` получает `id` сохранённой категории («Все категории» сразу выбирают новую).
struct CategoryEditorSheet: View {
    let mode: CategoryEditorMode
    var onSaved: (UUID) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @State private var model: CategoryFormModel?

    var body: some View {
        NavigationStack {
            if let model, !model.isDeleted {
                CategoryEditorForm(model: model, onSaved: onSaved)
            } else {
                Theme.canvasElevated.ignoresSafeArea()
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if model == nil {
                model = CategoryFormModel(mode: mode, store: ExpenseStore(context: modelContext))
            }
        }
    }
}

private struct CategoryEditorForm: View {
    @Bindable var model: CategoryFormModel
    let onSaved: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isConfirmingDelete = false
    @State private var isPickingReassignTarget = false
    @State private var saveFailures = 0

    /// Между разделами шита (макет `11-category`).
    private static let sectionSpacing: CGFloat = Theme.Spacing.xl + Theme.Spacing.sm

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                kindSection
                previewSection
                nameSection
                colorSection
                iconSection
                if model.isEditing {
                    manageSection
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            AuraBackground(tones: [auraTone], base: Theme.canvasElevated)
                .ignoresSafeArea()
        }
        .sheetHeader(
            model.title,
            onClose: { dismiss() },
            confirm: SheetConfirmAction(title: "cat.done", isEnabled: model.canSave, action: save)
        )
        .navigationDestination(for: ParentPickerRoute.self) { _ in
            CategoryParentPicker(candidates: model.parentCandidates, selection: $model.parentID)
        }
        .failureAlert($model.alert)
        .confirmationDialog(deleteTitle, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(deleteButtonTitle, role: .destructive) {
                if model.delete(reassignTo: model.defaultReassignTarget) { dismiss() }
            }
            if model.expenseCount > 0 {
                Button("catDelete.move") { isPickingReassignTarget = true }
            }
        } message: {
            Text(verbatim: deleteMessage)
        }
        .sheet(isPresented: $isPickingReassignTarget) {
            CategoryReassignSheet(excludedID: model.categoryID) { target in
                if model.delete(reassignTo: target) { dismiss() }
            }
        }
        .sensoryFeedback(Haptic.warning, trigger: isConfirmingDelete) { _, isShown in isShown }
        .sensoryFeedback(Haptic.error, trigger: saveFailures)
    }

    // MARK: - Разделы

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CategoryKindPicker(
                selection: $model.kind,
                isGroupEnabled: !model.isGroupBlocked,
                isSubcategoryEnabled: !model.isSubcategoryBlocked
            )
            if let footnote = model.kindFootnote {
                Text(footnote)
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }

    private var previewSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            CategoryChipPreview(
                name: model.trimmedName,
                placeholder: "cat.name.label",
                iconName: model.iconName,
                fill: previewFill,
                iconColor: auraTone.onArea
            )
            .padding(.vertical, Theme.Spacing.sm)
            Group {
                if model.kind == .group {
                    Text("cat.preview.caption.group")
                } else if let parent = model.parent {
                    Text(verbatim: L10n.format("cat.preview.caption", parent.name))
                }
            }
            .typeStyle(.footnote)
            .foregroundStyle(Theme.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("cat.name.label")
                    .typeStyle(.callout)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
                TextField(text: $model.name, prompt: Text(namePlaceholder).foregroundStyle(Theme.placeholder)) {
                    Text("cat.name.label")
                }
                .typeStyle(.body)
                .foregroundStyle(Theme.ink)
                .submitLabel(.done)
                // Подпись из `TextField(label:)` в дерево доступности не попадает — VoiceOver читал только пример.
                .accessibilityLabel(Text("cat.name.label"))
                .paperField()
                .errorShake(trigger: saveFailures)
                if model.isDuplicateName {
                    Text("cat.name.duplicate")
                        .typeStyle(.footnote)
                        .foregroundStyle(Theme.destructive)
                        .padding(.horizontal, Theme.Spacing.xs)
                }
            }
            if model.kind == .subcategory {
                parentRow
            }
        }
    }

    /// «Категория ›». На AX-размерах, если не помещается в ряд, — столбиком, как `SettingsRow`: родитель под
    /// подписью, иначе подпись рвётся по слогам («Ка-те-…»).
    private var parentRow: some View {
        NavigationLink(value: ParentPickerRoute()) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    ViewThatFits(in: .horizontal) {
                        parentRowInline
                        parentRowStacked
                    }
                } else {
                    parentRowInline
                }
            }
            .paperField()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: L10n.format("cat.group.a11y", model.parent?.name ?? "")))
        .accessibilityHint(Text("cat.group.a11y.hint"))
        .accessibilityAddTraits(.isButton)
    }

    private var parentRowInline: some View {
        HStack(spacing: Theme.Spacing.sm) {
            parentLabel
            Spacer(minLength: Theme.Spacing.sm)
            parentValue
                .lineLimit(1)
            parentChevron
        }
    }

    private var parentRowStacked: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                parentLabel
                HStack(spacing: Theme.Spacing.sm) {
                    parentValue
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
            Spacer(minLength: 0)
            parentChevron
        }
    }

    private var parentLabel: some View {
        Text("cat.group.label")
            .typeStyle(.body)
            .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var parentValue: some View {
        if let parent = model.parent {
            let tone = model.parentTone
            MiniPlaque(iconName: parent.iconName, fill: tone.main, iconColor: Theme.paper)
            Text(verbatim: parent.name)
                .typeStyle(.body)
                .foregroundStyle(Theme.secondary)
        }
    }

    private var parentChevron: some View {
        Image(systemName: "chevron.right")
            .typeStyle(.footnoteStrong)
            .foregroundStyle(Theme.graphic)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var colorSection: some View {
        if let ladder = model.ladder {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeading("cat.color.heading")
                ShadeLadderView(state: ladder, currentName: model.trimmedName, parentName: model.parent?.name ?? "")
                Text(ladder.overflows ? LocalizedStringKey("cat.shades.overflow") : LocalizedStringKey("cat.color.foot"))
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        } else if model.kind == .group {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                sectionHeading("cat.color.heading.group")
                ToneGridPicker(selection: $model.tone, occupied: model.occupiedTones)
            }
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeading("cat.icon.heading")
            IconGridPicker(
                selection: $model.iconName,
                selectedFill: previewFill,
                selectedIconColor: previewLabel,
                shadowTone: auraTone
            )
        }
    }

    private var manageSection: some View {
        SettingsGroup(footer: "cat.archive.foot") {
            Button {
                model.toggleArchive()
            } label: {
                manageRow(model.isArchived ? "cat.unarchive" : "cat.archive", color: Theme.ink)
            }
            Button {
                isConfirmingDelete = true
            } label: {
                manageRow("cat.delete", color: Theme.destructive)
            }
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
    }

    private func manageRow(_ title: LocalizedStringKey, color: Color) -> some View {
        Text(title)
            .typeStyle(.body)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: SettingsLayout.rowHeight, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .contentShape(Rectangle())
    }

    private func sectionHeading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .typeStyle(.headline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Цвета и тексты

    /// Тон ауры и превью: у категории — свой, у подкатегории — родителя.
    private var auraTone: GouacheTone {
        model.kind == .group ? model.tone : model.parentTone
    }

    /// Цвет карточки и выбранной иконки: основной тон категории или ступень подкатегории.
    private var previewFill: Color {
        if let ladder = model.ladder { return ladder.tone.shade(ladder.currentStep) }
        return model.tone.main
    }

    /// Иконка на `previewFill`.
    private var previewLabel: Color {
        if let ladder = model.ladder { return ladder.tone.labelOnShade(ladder.currentStep) }
        return model.tone.labelOnMain
    }

    private var namePlaceholder: LocalizedStringKey {
        model.kind == .group ? "cat.name.placeholder.group" : "cat.name.placeholder.sub"
    }

    private var deleteButtonTitle: LocalizedStringKey {
        model.originalKind == .group ? "catDelete.button.group" : "catDelete.button.sub"
    }

    private var deleteTitle: String {
        L10n.format(model.originalKind == .group ? "catDelete.confirm.group" : "catDelete.confirm.sub", model.originalName)
    }

    /// Текст удаления с числами; без трат и подкатегорий — только «Отменить это нельзя.».
    private var deleteMessage: String {
        switch model.originalKind {
        case .subcategory where model.expenseCount > 0:
            L10n.format("cat.delete.sub.body", model.expenseCount, model.originalParentName ?? "")
        case .group where model.expenseCount > 0 || model.subcategoryCount > 0:
            // TODO(copy): форм без подкатегорий («5 трат останутся без категории») и без трат в copy.json нет.
            L10n.format("cat.delete.group.body", model.subcategoryCount, model.expenseCount)
        default:
            String(localized: "catDelete.confirmMessage")
        }
    }

    // MARK: - Действия

    private func save() {
        if let id = model.save() {
            onSaved(id)
            dismiss()
        } else {
            saveFailures += 1
            if model.isDuplicateName {
                AccessibilityNotification.Announcement(String(localized: "cat.name.duplicate")).post()
            }
        }
    }
}

/// Переход к выбору родителя внутри шита.
private struct ParentPickerRoute: Hashable {}

#if DEBUG
#Preview("Новая категория") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CategoryEditorSheet(mode: .create())
        }
        .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
#endif
