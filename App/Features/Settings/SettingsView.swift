import SwiftData
import SwiftUI
import ExpenseCore

/// Вкладка «Настройки»: валюта, категории, резервная копия, версия.
struct SettingsView: View {
    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @AppStorage(BackupModel.lastExportDateKey) private var lastExportTimestamp: Double = 0
    @Environment(\.modelContext) private var modelContext
    @State private var backup = BackupModel()

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    CurrencyPickerView()
                } label: {
                    LabeledContent("Валюта", value: currencyCode)
                }
            } footer: {
                Text("Смена валюты меняет только обозначение: уже введённые суммы не пересчитываются.")
            }

            Section {
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Категории", systemImage: "square.grid.2x2")
                }
            }

            backupSection

            Section("О приложении") {
                LabeledContent("Версия", value: Self.appVersion)
            }

            #if DEBUG
            DebugDataSection()
            #endif
        }
        .navigationTitle("Настройки")
        .sheet(item: $backup.importSession) { session in
            ImportView(session: session)
        }
        .errorAlert($backup.errorMessage)
    }

    private var backupSection: some View {
        Section {
            // Экспорт и импорт висят на разных кнопках: два файловых диалога на одном view конфликтуют.
            Button {
                backup.prepareExport(context: modelContext, currencyCode: currencyCode)
            } label: {
                Label("Экспортировать в файл", systemImage: "square.and.arrow.up")
            }
            .fileExporter(
                isPresented: $backup.isExporterPresented,
                document: backup.exportDocument,
                contentTypes: BackupDocument.readableContentTypes,
                defaultFilename: backup.exportFileName,
                onCompletion: { result in
                    if backup.finishExport(result) {
                        lastExportTimestamp = Date.now.timeIntervalSince1970
                    }
                },
                onCancellation: { backup.cancelExport() }
            )

            Button {
                backup.isImporterPresented = true
            } label: {
                Label("Импортировать из файла", systemImage: "square.and.arrow.down")
            }
            .fileImporter(
                isPresented: $backup.isImporterPresented,
                allowedContentTypes: BackupDocument.readableContentTypes
            ) { result in
                backup.openImportedFile(result)
            }
        } header: {
            Text("Резервная копия")
        } footer: {
            Text(lastExportText)
        }
    }

    private var lastExportText: String {
        guard lastExportTimestamp > 0 else { return "Экспорт ещё не выполнялся." }
        let date = Date(timeIntervalSince1970: lastExportTimestamp)
        return "Последний экспорт: \(date.formatted(date: .long, time: .shortened))."
    }

    /// «1.0.0 (1)» из Info.plist.
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
