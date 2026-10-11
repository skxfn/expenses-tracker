import SwiftData
import SwiftUI
import ExpenseCore

/// «Настройки» (макет `12-settings`): пуш из ⚙ на главной, системная кнопка «Назад», Large Title,
/// группы r 22 на бумаге с аурой. Валюта, категории, вид диаграммы на вкладке «Траты», резервная копия,
/// версия и лицензии. Корень экрана — этот тип; стек навигации даёт оболочка.
struct SettingsView: View {
    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @AppStorage(SettingsKeys.currencySymbolStyle) private var symbolStyle = CurrencySymbolStyle.default
    @AppStorage(SettingsKeys.homeOverviewStyle) private var overviewStyle = HomeOverviewStyle.default
    @AppStorage(BackupModel.lastExportDateKey) private var lastExportTimestamp: Double = 0
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder), SortDescriptor(\ExpenseCategory.createdAt)])
    private var categories: [ExpenseCategory]

    @Environment(\.modelContext) private var modelContext
    @State private var backup = BackupModel()
    @State private var auraTones: [GouacheTone] = []

    /// Сколько держится тост «Копия сохранена».
    private static let toastDuration: Duration = .seconds(3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
                generalGroup
                SettingsGroup(header: "settings.overview.heading") {
                    OverviewStylePicker(selection: $overviewStyle)
                }
                backupGroup
                aboutGroup
                #if DEBUG
                DebugDataSection()
                #endif
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .settingsBackground(tones: auraTones)
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $backup.importSession) { session in
            ImportView(session: session)
        }
        .failureAlert($backup.alert)
        .glassToast(isPresented: backup.isExportDoneToastShown) {
            GlassToast(message: "settings.backup.exportDone")
        }
        .task(id: backup.isExportDoneToastShown) {
            guard backup.isExportDoneToastShown else { return }
            AccessibilityNotification.Announcement(String(localized: "settings.backup.exportDone")).post()
            try? await Task.sleep(for: Self.toastDuration)
            backup.isExportDoneToastShown = false
        }
        .onAppear(perform: loadAuraTones)
    }

    // MARK: - Группы

    /// «Обозначение»: знак рубля (по умолчанию) | BYN — только для BYN (INTEGRATION §3.3.1, макет `12-settings`).
    /// Для VoiceOver строка — один регулируемый элемент «Обозначение, Знак рубля»: подсказку на контейнере
    /// сегмента VoiceOver не читает, а у регулируемого элемента — читает.
    private var symbolRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("settings.currency.symbol")
                .typeStyle(.body)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: Theme.Spacing.sm)
            GlassSegmentedControl(
                title: "settings.currency.symbol",
                selection: $symbolStyle,
                items: [
                    .init(
                        value: .sign,
                        title: LocalizedStringKey(MoneyFormatter.belarusianRubleSign),
                        accessibilityTitle: "settings.currency.symbol.sign.a11y"
                    ),
                    .init(value: .code, title: "settings.currency.symbol.code")
                ]
            )
            .frame(width: Theme.Size.symbolStylePicker)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(minHeight: Theme.Size.field)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("settings.currency.symbol"))
        .accessibilityValue(Text(LocalizedStringKey(
            symbolStyle == .sign ? "settings.currency.symbol.sign.a11y" : "settings.currency.symbol.code"
        )))
        .accessibilityHint(Text("settings.currency.symbol.a11y.hint"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: symbolStyle = .code
            case .decrement: symbolStyle = .sign
            @unknown default: break
            }
        }
    }

    private var generalGroup: some View {
        let topLevel = categories.filter { $0.parent == nil && !$0.isArchived }
        let subcategoryCount = categories.filter { !$0.isArchived && $0.parent.map { !$0.isArchived } == true }.count
        let currency = CurrencyOption(code: currencyCode)
        return SettingsGroup {
            NavigationLink {
                CurrencyPickerView()
            } label: {
                SettingsRow("settings.currency", value: currency.nameWithSymbol(style: symbolStyle), showsChevron: true)
            }
            .accessibilityLabel(Text("settings.currency"))
            .accessibilityValue(Text(verbatim: currency.spokenNameWithSymbol(style: symbolStyle)))
            if currencyCode == MoneyFormatter.belarusianRubleCode {
                symbolRow
            }
            NavigationLink {
                CategoriesView()
            } label: {
                SettingsRow(title: "settings.categories", value: "\(topLevel.count)", showsChevron: true) {
                    CategoryFan(tones: CategoryFan.tones(of: topLevel))
                }
            }
            .accessibilityLabel(Text(verbatim: L10n.format("settings.categories.a11y", topLevel.count, subcategoryCount)))
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
    }

    private var backupGroup: some View {
        SettingsFootnoted(lastExportText) {
            SettingsGroup(header: "settings.backup.heading") {
                // Сохранение и восстановление висят на разных кнопках: два файловых окна на одном view конфликтуют.
                Button {
                    Task { await backup.prepareExport(context: modelContext, currencyCode: currencyCode) }
                } label: {
                    actionRow("settings.backup.export", systemImage: "square.and.arrow.up", isBusy: backup.isPreparingExport)
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
                    actionRow("settings.backup.import", systemImage: "square.and.arrow.down", isBusy: backup.isReadingImport)
                }
                .fileImporter(
                    isPresented: $backup.isImporterPresented,
                    allowedContentTypes: BackupDocument.readableContentTypes
                ) { result in
                    Task { await backup.openImportedFile(result) }
                }
            }
            .buttonStyle(.pressable(Motion.PressScale.row))
            // Пока копия готовится или читается, повторное нажатие ничего не запускает.
            .disabled(backup.isBusy)
        }
    }

    private var aboutGroup: some View {
        SettingsGroup(header: "settings.about.heading") {
            SettingsRow("settings.about.version", value: Self.appVersion)
                .accessibilityElement(children: .combine)
            NavigationLink {
                LicensesView()
            } label: {
                SettingsRow("settings.about.licenses", showsChevron: true)
            }
            .buttonStyle(.pressable(Motion.PressScale.row))
        }
    }

    /// Строка-действие: подпись слева, иконка справа (макет: «Сохранить копию ⇪»); пока действие идёт —
    /// индикатор вместо иконки.
    private func actionRow(_ title: LocalizedStringKey, systemImage: String, isBusy: Bool) -> some View {
        SettingsRow(title: title) {
            if isBusy {
                // TODO(copy): подписи «идёт сохранение/восстановление» в copy.json нет — VoiceOver назовёт системное «Выполняется».
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .typeStyle(.headline)
                    .foregroundStyle(Theme.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Данные

    /// «Последняя копия: 1 окт» (дата D7, год — если не текущий) или «Копий ещё не было».
    private var lastExportText: String {
        guard lastExportTimestamp > 0 else { return String(localized: "settings.backup.never") }
        let date = Date(timeIntervalSince1970: lastExportTimestamp)
        return L10n.format("settings.backup.last", AppLanguage.current.dateFormatter(calendar: .current, now: .now).short(date))
    }

    /// «1.0.0 (1)» из Info.plist: сборка нужна при установке через SideStore (`settings.about.version` → why).
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// Аура — тинты крупнейших категорий текущего месяца, как на главной; без трат — чистая бумага.
    private func loadAuraTones() {
        guard
            let month = Calendar.current.dateInterval(of: .month, for: .now),
            let expenses = try? ExpenseStore(context: modelContext).expenses(in: month)
        else { return }
        var totals: [GouacheTone: Int64] = [:]
        for expense in expenses {
            guard
                let group = expense.category?.parent ?? expense.category,
                let tone = GouacheTone(mainHex: group.colorHex)
            else { continue }
            totals[tone, default: 0] += expense.amountMinor
        }
        auraTones = totals.sorted { $0.value > $1.value }.prefix(AuraBackground.defaultLayout.count).map(\.key)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
#endif
