import PhotosUI
import UIKit
import SwiftData
import SwiftUI
import ExpenseCore

/// Шит ИИ-записи: ввод текстом или фото → черновики → «Записать». Открывается из шита записи
/// (`router.presentAssistant()`); ничего не сохраняется без нажатия «Записать».
struct AssistantSheet: View {
    var startsWithCamera = false

    @State private var model: AssistantModel
    @State private var isConfirmingDiscard = false
    @Environment(\.dismiss) private var dismiss

    /// `defaultDate` — дата из шита записи для трат, у которых модель даты не назвала.
    init(defaultDate: EntryDate = .today) {
        _model = State(initialValue: AssistantModel.make(defaultDate: defaultDate))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let review = model.review {
                    DraftReviewView(model: review, onEditInput: model.backToInput, onSaved: { dismiss() })
                } else {
                    AssistantInputView(model: model, startsWithCamera: startsWithCamera)
                }
            }
            .sheetHeader(model.review == nil ? "assistant.title" : "assistant.review.title", onClose: close)
            .background(Theme.canvasElevated)
        }
        .presentationBackground(Theme.canvasElevated)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(hasUnsavedWork)
        .confirmationDialog("assistant.discard.title", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("assistant.discard.discard", role: .destructive) {
                model.cancel()
                dismiss()
            }
            Button("assistant.discard.keep", role: .cancel) {}
        }
    }

    /// Введённый текст или фото, отправленный запрос, черновики — закрытие спрашивает.
    private var hasUnsavedWork: Bool {
        model.review != nil || model.isSending || model.hasInput
    }

    private func close() {
        if hasUnsavedWork {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }
}

/// Ввод: поле (можно диктовать с клавиатуры — распознавание речи на iPhone), фото чека с камеры или из фотоплёнки,
/// «Разобрать». Ошибка — над кнопкой; ввод при ней не теряется.
struct AssistantInputView: View {
    @Bindable var model: AssistantModel
    let startsWithCamera: Bool

    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false
    @FocusState private var isFieldFocused: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var money

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !model.isConfigured {
                    notConfiguredNotice
                }
                field
                if !model.photos.isEmpty {
                    photoStrip
                }
                sourceButtons
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .bottom, spacing: 0) {
            VStack(spacing: Theme.Spacing.sm) {
                if let error = model.error {
                    errorBanner(error)
                }
                actionButton
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.md)
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            DocumentCamera(
                onScan: { pages in
                    pages.forEach(model.addPhoto)
                    isShowingCamera = false
                },
                onCancel: { isShowingCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
        .task {
            #if DEBUG
            if AssistantDebug.isStubbed, AssistantDebug.scenario != nil {
                if AssistantDebug.scenario == "receipt", model.photos.isEmpty, let sample = UIImage(systemName: "doc.text")?.pngData() {
                    model.addPhoto(sample)
                }
                model.send(context: modelContext, formatter: money)
                return
            }
            #endif
            if startsWithCamera, DocumentCamera.isAvailable {
                isShowingCamera = true
            } else {
                isFieldFocused = true
            }
        }
    }

    // MARK: - Части

    private var field: some View {
        TextField("assistant.input.placeholder", text: $model.text, axis: .vertical)
            .lineLimit(4...10)
            .typeStyle(.body)
            .foregroundStyle(Theme.ink)
            .focused($isFieldFocused)
            .padding(Theme.Spacing.md)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
            .disabled(model.isSending)
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(model.photos) { photo in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let thumbnail = photo.thumbnail {
                                Image(uiImage: thumbnail).resizable().scaledToFill()
                            } else {
                                Theme.surface
                            }
                        }
                        .frame(width: 72, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.plaque, style: .continuous))
                        .accessibilityHidden(true)

                        Button {
                            model.removePhoto(photo.id)
                        } label: {
                            Label("assistant.photo.remove.a11y", systemImage: "xmark")
                        }
                        .buttonStyle(.glassCircle(diameter: 28))
                        .offset(x: 6, y: -6)
                        .disabled(model.isSending)
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                }
            }
        }
    }

    private var sourceButtons: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if DocumentCamera.isAvailable {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("assistant.camera", systemImage: "doc.viewfinder")
                }
                .buttonStyle(.glassCapsule(height: Theme.Size.chip, expands: false))
            }
            PhotosPicker(
                selection: $pickedItems,
                maxSelectionCount: max(AssistantModel.maxPhotos - model.photos.count, 1),
                matching: .images
            ) {
                Label("assistant.photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.glassCapsule(height: Theme.Size.chip, expands: false))
        }
        .disabled(model.isSending || !model.canAddPhotos)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var actionButton: some View {
        if model.isSending {
            HStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text("assistant.parsing")
                    .typeStyle(.callout)
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button("assistant.cancel", action: model.cancel)
                    .buttonStyle(.glassCapsule(height: Theme.Size.chip, expands: false))
            }
            .frame(minHeight: Theme.Size.actionButton)
            .accessibilityElement(children: .contain)
        } else {
            Button(model.error?.isRetryable == true ? "assistant.retry" : "assistant.parse") {
                isFieldFocused = false
                model.send(context: modelContext, formatter: money)
            }
            .buttonStyle(.glassCapsule(.prominent))
            .disabled(!model.canSend)
        }
    }

    private func errorBanner(_ error: AssistantError) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(LocalizedStringKey(AssistantText.errorKey(error)))
                .typeStyle(.callout)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if error.needsSettings {
                NavigationLink("assistant.openSettings") {
                    AssistantSettingsView()
                }
                .typeStyle(.footnoteStrong)
                .foregroundStyle(Theme.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var notConfiguredNotice: some View {
        NavigationLink {
            AssistantSettingsView()
        } label: {
            HStack {
                Text("assistant.notConfigured")
                    .typeStyle(.callout)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.graphic)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
    }

    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                model.addPhoto(data)
            }
        }
        pickedItems = []
    }
}

/// Ключи текстов ИИ-записи из переменных: `Text("ключ.\(x)")` искал бы ключ `ключ.%@` (ловушка AGENTS.md).
enum AssistantText {
    static func errorKey(_ error: AssistantError) -> String {
        "error.assistant." + error.rawValue
    }

    static func message(for error: AssistantError) -> String {
        String(localized: String.LocalizationValue(errorKey(error)))
    }
}
