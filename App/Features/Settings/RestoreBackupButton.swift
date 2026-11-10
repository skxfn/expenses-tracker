import SwiftUI
import ExpenseCore

/// «Восстановить из резервной копии» вне настроек — на пустой вкладке «Траты» после переустановки:
/// выбор файла копии → тот же `ImportView`, что в настройках.
///
/// Окно выбора и шит висят на экране (`restoreBackupHost()`), а не на кнопке: кнопка пропадает вместе с пустым
/// состоянием, как только данные восстановлены, и шит с отчётом закрылся бы вместе с ней.
struct RestoreBackupButton: View {
    @Environment(BackupModel.self) private var backup: BackupModel?

    var body: some View {
        if let backup {
            Button {
                backup.isImporterPresented = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("home.empty.firstRun.restore")
                    if backup.isReadingImport {
                        ProgressView()
                            .accessibilityLabel(Text("settings.backup.import.busy.a11y"))
                    }
                }
            }
            .buttonStyle(.glassCapsule(.glass, height: Theme.Size.chip, expands: false))
            .disabled(backup.isBusy)
        }
    }
}

extension View {
    /// Окно выбора копии и `ImportView` для `RestoreBackupButton` внутри этого экрана.
    func restoreBackupHost() -> some View {
        modifier(RestoreBackupHost())
    }
}

private struct RestoreBackupHost: ViewModifier {
    @State private var backup = BackupModel()
    @Environment(AutoBackupModel.self) private var autoBackup: AutoBackupModel?

    func body(content: Content) -> some View {
        content
            .environment(backup)
            .fileImporter(isPresented: $backup.isImporterPresented, allowedContentTypes: BackupDocument.readableContentTypes) { result in
                Task { await backup.openImportedFile(result) }
            }
            // Окно открывается в папке автокопии, если она известна.
            .fileDialogDefaultDirectory(autoBackup?.folderURL)
            .sheet(item: $backup.importSession) { session in
                ImportView(session: session)
            }
            .failureAlert($backup.alert)
    }
}
