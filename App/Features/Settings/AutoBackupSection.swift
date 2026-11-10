import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import ExpenseCore

/// «Автокопия в облако» в настройках: переключатель, папка, «Сохранить сейчас» и сноска со статусом
/// (как работает · последняя копия · ошибка). Первое включение открывает выбор папки; если в папке уже лежит
/// незнакомая копия — диалог «Восстановить из копии» / «Заменить копию».
/// Состояние — `AutoBackupModel` из окружения: её же вызывают сохранения данных и уход приложения в фон.
struct AutoBackupSection: View {
    /// Восстановление из копии найденной папки — на экране настроек (`ImportView`).
    let onRestore: (ImportSession) -> Void

    @Environment(AutoBackupModel.self) private var model
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var model = model
        SettingsFootnoted(footnote) {
            SettingsGroup(header: "settings.autoBackup.heading") {
                toggleRow
                if model.isEnabled {
                    folderRow
                    saveNowRow
                }
            }
            .buttonStyle(.pressable(Motion.PressScale.row))
        }
        .fileImporter(isPresented: $model.isFolderPickerPresented, allowedContentTypes: [.folder]) { result in
            Task { await model.folderPicked(result, container: modelContext.container) }
        }
        .confirmationDialog(
            "autoBackup.existing.title",
            isPresented: Binding(get: { model.candidate != nil }, set: { if !$0 { model.candidate = nil } }),
            titleVisibility: .visible,
            presenting: model.candidate
        ) { candidate in
            if case .readable = candidate.existing {
                Button("settings.backup.import") {
                    if let session = model.restore(from: candidate) { onRestore(session) }
                }
            }
            Button("autoBackup.existing.replace", role: .destructive) {
                model.replaceCopy(of: candidate, container: modelContext.container)
            }
        } message: { candidate in
            Text(verbatim: message(for: candidate))
        }
        .failureAlert($model.alert)
    }

    // MARK: - Строки

    /// Пока открыт выбор папки после включения, переключатель стоит во «вкл»; отмена выбора вернёт его.
    private var toggleRow: some View {
        Toggle(isOn: Binding(
            get: { model.isToggleOn },
            set: { model.setEnabled($0, container: modelContext.container) }
        )) {
            Text("settings.autoBackup.toggle")
                .typeStyle(.body)
                .foregroundStyle(Theme.ink)
        }
        .tint(Theme.prominent)
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(minHeight: SettingsLayout.rowHeight)
    }

    /// «Папка · iCloud Drive/Траты ›»; недоступная папка — строка-действие «Выбрать папку заново».
    private var folderRow: some View {
        Button {
            model.isFolderPickerPresented = true
        } label: {
            if model.problem == .folderUnavailable {
                SettingsRow(title: "settings.autoBackup.chooseAgain") {
                    rowIcon("folder")
                }
            } else {
                SettingsRow("settings.autoBackup.folder", value: model.folderName, showsChevron: true)
            }
        }
    }

    /// Пока копия пишется (и автоматическая тоже) — индикатор вместо иконки, повторно не нажимается.
    private var saveNowRow: some View {
        Button {
            model.saveNow(container: modelContext.container)
        } label: {
            SettingsRow(title: "settings.autoBackup.now") {
                if model.isWriting {
                    ProgressView()
                        .accessibilityLabel(Text("settings.backup.export.busy.a11y"))
                } else {
                    rowIcon("arrow.clockwise")
                }
            }
        }
        .disabled(model.isWriting)
    }

    private func rowIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .typeStyle(.headline)
            .foregroundStyle(Theme.secondary)
            .accessibilityHidden(true)
    }

    // MARK: - Тексты

    private var footnote: String {
        guard model.isEnabled else { return String(localized: "settings.autoBackup.footer") }
        switch model.problem {
        case .folderUnavailable: return String(localized: "settings.autoBackup.error.folder")
        case .writeFailed: return String(localized: "settings.autoBackup.error.write")
        case nil: break
        }
        guard let date = model.lastBackupDate else { return String(localized: "settings.backup.never") }
        return Self.lastBackupText(date, now: .now, calendar: .current)
    }

    /// «Последняя копия: сегодня, 14:05» · «вчера, 14:05» · «8 ноя, 14:05» (дата D7, время 24-часовое).
    static func lastBackupText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = AppLanguage.current.dateFormatter(calendar: calendar, now: now)
        let time = formatter.hour(date)
        if calendar.isDate(date, inSameDayAs: now) {
            return L10n.format("settings.autoBackup.last.today", time)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return L10n.format("settings.autoBackup.last.yesterday", time)
        }
        return L10n.format("settings.autoBackup.last.date", formatter.short(date), time)
    }

    /// «Копия от 8 ноя — 1234 траты…»; нечитаемая копия — без подробностей.
    private func message(for candidate: AutoBackupModel.FolderCandidate) -> String {
        guard case .readable(let payload) = candidate.existing else {
            return String(localized: "autoBackup.existing.unreadable")
        }
        let date = AppLanguage.current.dateFormatter(calendar: .current, now: .now).short(payload.exportedAt)
        return L10n.format("autoBackup.existing.message", date, payload.expenses.count)
    }
}
