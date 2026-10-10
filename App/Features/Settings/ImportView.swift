import SwiftData
import SwiftUI
import ExpenseCore

/// Восстановление из копии (шит в стиле настроек, `import.*`): сведения о файле → «Объединить с текущими»
/// или «Заменить всё» (с подтверждением) → отчёт и вопрос о валюте. Для файла формата 1 — строка `import.v1`.
struct ImportView: View {
    @Bindable var session: ImportSession

    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var replaceCounts: ReplaceCounts?

    /// Сколько удалится при замене — для текста подтверждения.
    private struct ReplaceCounts {
        let expenses: Int
        let categories: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
                    if let report = session.report {
                        reportContent(report)
                    } else {
                        previewContent
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.lg)
            }
            .background(Theme.canvasElevated)
            .sheetHeader(
                session.report == nil ? "import.title" : "import.titleDone",
                onClose: { dismiss() },
                confirm: session.report == nil ? nil : SheetConfirmAction(title: "import.done") { dismiss() }
            )
        }
        .failureAlert($session.alert)
    }

    // MARK: - До восстановления

    @ViewBuilder
    private var previewContent: some View {
        let payload = session.payload
        let fileCurrency = CurrencyOption(code: payload.currencyCode)
        let footer = payload.currencyCode == currencyCode ? nil : L10n.format("import.currencyDiff", payload.currencyCode)
        SettingsFootnoted(footer) {
            SettingsGroup(header: "import.file") {
                SettingsRow("import.created", value: dateFormatter.dayMonth(payload.exportedAt))
                SettingsRow("import.currency", value: fileCurrency.nameWithCode)
                SettingsRow("import.categories", value: number(payload.categories.count))
                SettingsRow("import.expenses", value: number(payload.expenses.count))
            }
        }

        modeButton("import.merge", footer: "import.mergeFooter", kind: .glass) {
            session.apply(.merge, context: modelContext)
        }
        modeButton("import.replace", footer: "import.replaceFooter", kind: .destructive) {
            replaceCounts = ReplaceCounts(
                expenses: (try? modelContext.fetchCount(FetchDescriptor<Expense>())) ?? 0,
                categories: (try? modelContext.fetchCount(FetchDescriptor<ExpenseCategory>())) ?? 0
            )
        }
        .confirmationDialog(
            "import.replaceConfirm",
            isPresented: Binding(get: { replaceCounts != nil }, set: { if !$0 { replaceCounts = nil } }),
            titleVisibility: .visible,
            presenting: replaceCounts
        ) { _ in
            Button("import.replaceConfirmButton", role: .destructive) {
                session.apply(.replace, context: modelContext)
            }
        } message: { counts in
            Text(verbatim: L10n.format("import.replaceConfirmMessage", counts.expenses, counts.categories))
        }
    }

    private func modeButton(
        _ title: LocalizedStringKey,
        footer: LocalizedStringKey,
        kind: GlassCapsuleButtonStyle.Kind,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button(title, action: action)
                .buttonStyle(.glassCapsule(kind))
            Text(footer)
                .typeStyle(.footnote)
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    // MARK: - После восстановления

    @ViewBuilder
    private func reportContent(_ report: ImportReport) -> some View {
        if report.isFromPreviousFormat {
            SettingsGroup {
                messageRow(String(localized: "import.v1"))
            }
        }
        if session.needsCurrencyDecision(currentCode: currencyCode) {
            currencyQuestion(fileCode: report.currencyCode)
        }
        countsGroup("import.reportCategories", counts: report.categories)
        let missing = report.expensesWithMissingCategory
        SettingsFootnoted(missing > 0 ? L10n.format("import.missingCategory", missing) : nil) {
            countsGroup("import.reportExpenses", counts: report.expenses)
        }
    }

    private func currencyQuestion(fileCode: String) -> some View {
        let file = CurrencyOption(code: fileCode)
        let current = CurrencyOption(code: currencyCode)
        return SettingsGroup(header: "import.currencyHeader") {
            messageRow(L10n.format("import.currencyQuestion", file.name, file.code, current.name, current.code))
            actionRow(L10n.format("import.useCurrency", file.code)) {
                currencyCode = file.code
                session.answerCurrencyQuestion()
            }
            actionRow(L10n.format("import.keepCurrency", current.code)) {
                session.answerCurrencyQuestion()
            }
        }
    }

    private func countsGroup(_ title: LocalizedStringKey, counts: ImportReport.Counts) -> some View {
        SettingsGroup(header: title) {
            SettingsRow("import.added", value: number(counts.added))
            SettingsRow("import.updated", value: number(counts.updated))
            SettingsRow("import.unchanged", value: number(counts.unchanged))
            if counts.deleted > 0 {
                SettingsRow("import.deleted", value: number(counts.deleted))
            }
        }
    }

    private func messageRow(_ text: String) -> some View {
        Text(verbatim: text)
            .typeStyle(.body)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
    }

    private func actionRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .typeStyle(.body)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: SettingsLayout.rowHeight, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.lg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
    }

    /// Число с разрядами через U+00A0.
    private func number(_ value: Int) -> String {
        TextSpacing.normalized(value.formatted(.number.locale(.app)))
    }

    private var dateFormatter: any DateTextFormatter {
        AppLanguage.current.dateFormatter(calendar: .current, now: .now)
    }
}
