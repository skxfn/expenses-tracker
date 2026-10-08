import SwiftUI
import ExpenseCore

/// Импорт резервной копии: сведения о файле → выбор режима → отчёт и вопрос о валюте.
struct ImportView: View {
    @Bindable var session: ImportSession

    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingReplace = false

    var body: some View {
        NavigationStack {
            Form {
                if let report = session.report {
                    reportSections(report)
                } else {
                    previewSections
                }
            }
            .navigationTitle(session.report == nil ? "Импорт" : "Импорт завершён")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.report == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
            }
            .errorAlert($session.errorMessage)
        }
    }

    // MARK: - До импорта

    @ViewBuilder
    private var previewSections: some View {
        let payload = session.payload
        Section {
            LabeledContent("Создан", value: payload.exportedAt.formatted(date: .long, time: .shortened))
            LabeledContent("Валюта", value: CurrencyOption.displayName(for: payload.currencyCode))
            LabeledContent("Категорий", value: payload.categories.count.formatted())
            LabeledContent("Расходов", value: payload.expenses.count.formatted())
        } header: {
            Text("Файл")
        } footer: {
            if payload.currencyCode != currencyCode {
                Text("Валюта в файле отличается от текущей (\(currencyCode)). После импорта можно будет выбрать, какую оставить.")
            }
        }

        Section {
            Button("Объединить") {
                session.apply(.merge, context: modelContext)
            }
        } footer: {
            Text("Новые записи добавятся, совпадающие обновятся данными из файла. Ничего не удалится.")
        }

        Section {
            Button("Заменить всё", role: .destructive) {
                isConfirmingReplace = true
            }
            .confirmationDialog(
                "Заменить все данные?",
                isPresented: $isConfirmingReplace,
                titleVisibility: .visible
            ) {
                Button("Удалить текущие и загрузить из файла", role: .destructive) {
                    session.apply(.replace, context: modelContext)
                }
            } message: {
                Text("Все текущие категории и расходы будут удалены. Отменить это нельзя.")
            }
        } footer: {
            Text("Текущие категории и расходы удалятся и заменятся данными из файла.")
        }
    }

    // MARK: - После импорта

    @ViewBuilder
    private func reportSections(_ report: ImportReport) -> some View {
        if session.needsCurrencyDecision(currentCode: currencyCode) {
            Section {
                Text("В файле: \(CurrencyOption(code: report.currencyCode).name) (\(report.currencyCode)). В приложении: \(CurrencyOption(code: currencyCode).name) (\(currencyCode)). Суммы при смене не пересчитываются.")
                Button("Использовать \(report.currencyCode)") {
                    currencyCode = report.currencyCode
                    session.answerCurrencyQuestion()
                }
                Button("Оставить \(currencyCode)") {
                    session.answerCurrencyQuestion()
                }
            } header: {
                Text("Валюта")
            }
        }
        countsSection("Категории", counts: report.categories)
        countsSection("Расходы", counts: report.expenses)
        if report.expensesWithMissingCategory > 0 {
            Section {
                Text("Расходов без категории: \(report.expensesWithMissingCategory) — их категория не нашлась ни в файле, ни в приложении.")
            }
        }
    }

    private func countsSection(_ title: String, counts: ImportReport.Counts) -> some View {
        Section(title) {
            LabeledContent("Добавлено", value: counts.added.formatted())
            LabeledContent("Обновлено", value: counts.updated.formatted())
            LabeledContent("Без изменений", value: counts.unchanged.formatted())
            if counts.deleted > 0 {
                LabeledContent("Удалено", value: counts.deleted.formatted())
            }
        }
    }
}
