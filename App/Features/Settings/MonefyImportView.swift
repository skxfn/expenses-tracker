import SwiftData
import SwiftUI
import ExpenseCore

/// Перенос трат из Monefy (шит в стиле восстановления копии, `monefy.*`): сведения о файле → сопоставление
/// каждой категории Monefy с категорией или подкатегорией приложения («Все категории»), «Без категории»
/// или «Не переносить» → «Перенести N трат» → отчёт. Категории Monefy в приложении не создаются.
struct MonefyImportView: View {
    @Bindable var session: MonefyImportSession

    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @Query(sort: [SortDescriptor(\ExpenseCategory.sortOrder), SortDescriptor(\ExpenseCategory.createdAt)])
    private var categories: [ExpenseCategory]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.moneyFormatter) private var moneyFormatter
    @Environment(\.dismiss) private var dismiss
    /// Категория Monefy, для которой открыты «Все категории».
    @State private var pickingGroup: MonefyImportPlan.Group?
    @State private var newCategory: CategoryEditorMode?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
                    if let report = session.report {
                        reportContent(report)
                    } else {
                        fileContent
                        mappingContent
                        importButton
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.lg)
            }
            .background(Theme.canvasElevated)
            .sheetHeader(
                session.report == nil ? "monefy.title" : "monefy.titleDone",
                onClose: { dismiss() },
                confirm: session.report == nil ? nil : SheetConfirmAction(title: "import.done") { dismiss() }
            )
        }
        .interactiveDismissDisabled(session.isImporting)
        .failureAlert($session.alert)
        .sheet(item: $pickingGroup) { group in
            categoryPicker(for: group)
        }
    }

    // MARK: - До переноса

    @ViewBuilder
    private var fileContent: some View {
        let plan = session.plan
        let codes = plan.file.currencyCodes
        SettingsFootnoted(fileFootnote(codes: codes)) {
            SettingsGroup(header: "monefy.file") {
                SettingsRow("import.expenses", value: number(plan.expenseCount))
                if let period = periodText {
                    SettingsRow("monefy.period", value: period)
                }
                if !codes.isEmpty {
                    currencyRow(codes: codes)
                }
                if plan.notExpenseCount > 0 {
                    SettingsRow("monefy.notExpenses", value: number(plan.notExpenseCount))
                }
            }
        }
    }

    /// «Британский фунт стерлингов · GBP»; не помещается — только код (он же в сноске о валюте).
    /// Несколько валют — коды через запятую.
    private func currencyRow(codes: [String]) -> some View {
        let full = codes.count == 1 ? CurrencyOption(code: codes[0]).nameWithCode : codes.joined(separator: ", ")
        return SettingsRow(title: "import.currency") {
            ViewThatFits(in: .horizontal) {
                Text(verbatim: full)
                Text(verbatim: codes.joined(separator: ", "))
            }
            .typeStyle(.body)
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var mappingContent: some View {
        SettingsGroup(header: "monefy.categories", footer: "monefy.categoriesFooter") {
            ForEach(session.plan.groups) { group in
                mappingRow(group)
            }
        }
    }

    /// Строка категории Monefy — меню выбора: «Выбрать категорию» открывает «Все категории»,
    /// «Без категории» и «Не переносить» выбираются сразу (галочка у текущего).
    private func mappingRow(_ group: MonefyImportPlan.Group) -> some View {
        let target = session.mapping[group.name]
        let resolved = resolvedTarget(target)
        return Menu {
            Button {
                pickingGroup = group
            } label: {
                Label("monefy.target.choose", systemImage: "square.grid.2x2")
            }
            Picker(selection: simpleTargetBinding(for: group)) {
                Text("feed.row.noCategory").tag(MonefyCategoryTarget?.some(.uncategorized))
                Text("monefy.target.skip").tag(MonefyCategoryTarget?.some(.skip))
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            MonefyMappingRow(
                name: group.name,
                meta: L10n.format("monefy.group.meta", group.expenseCount, moneyFormatter.string(fromMinor: group.totalMinor)),
                target: resolved
            )
        }
        .accessibilityLabel(Text(verbatim: L10n.format(
            "monefy.group.a11y", group.name, group.expenseCount, EntrySpeech.money(group.totalMinor, formatter: moneyFormatter)
        )))
        .accessibilityValue(Text(verbatim: resolved?.title ?? String(localized: "monefy.target.none.a11y")))
        .accessibilityHint(Text("monefy.group.a11y.hint"))
    }

    /// Выбор «Без категории» / «Не переносить» в меню; категория приложения в нём не отмечается.
    private func simpleTargetBinding(for group: MonefyImportPlan.Group) -> Binding<MonefyCategoryTarget?> {
        Binding(
            get: {
                switch session.mapping[group.name] {
                case .uncategorized: .uncategorized
                case .skip: .skip
                case .category, nil: nil
                }
            },
            set: { target in
                if let target { session.select(target, for: group.name) }
            }
        )
    }

    private var importButton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button {
                Task { await session.apply(context: modelContext) }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(verbatim: L10n.format("monefy.import", session.importCount))
                    if session.isImporting {
                        ProgressView()
                            .tint(Theme.onInk)
                            .accessibilityLabel(Text("monefy.import.busy.a11y"))
                    }
                }
            }
            .buttonStyle(.glassCapsule(.prominent))
            .disabled(!session.canImport)
            // Подпись в одну строку: на самых крупных размерах — до AX1 и крупный просмотр по долгому нажатию.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityShowsLargeContentViewer()
            Text(verbatim: importFootnote)
                .typeStyle(.footnote)
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, Theme.Spacing.lg)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - После переноса

    private func reportContent(_ report: MonefyImportReport) -> some View {
        SettingsGroup(header: "import.reportExpenses") {
            SettingsRow("import.added", value: number(report.imported))
            SettingsRow("monefy.report.duplicates", value: number(report.duplicates))
            if report.excluded > 0 {
                SettingsRow("monefy.report.excluded", value: number(report.excluded))
            }
            if report.notExpenses > 0 {
                SettingsRow("monefy.notExpenses", value: number(report.notExpenses))
            }
        }
    }

    // MARK: - Выбор категории

    /// «Все категории» поверх шита: выбор сразу закрывает их; новая категория из них сразу выбирается.
    private func categoryPicker(for group: MonefyImportPlan.Group) -> some View {
        let selectedID: UUID? = if case .category(let id) = session.mapping[group.name] { id } else { nil }
        return CategoryPickerSheet(
            selectedID: selectedID,
            keepingID: nil,
            auraTones: [],
            onSelect: { choice in
                session.select(.category(choice.id), for: group.name)
                pickingGroup = nil
            },
            onCreateCategory: { name in
                newCategory = .create(name: name)
            }
        )
        .sheet(item: $newCategory) { mode in
            CategoryEditorSheet(mode: mode) { id in
                session.select(.category(id), for: group.name)
                pickingGroup = nil
            }
        }
    }

    // MARK: - Данные

    /// Выбор строки для показа; категория, удалённая после выбора, — как «не выбрано».
    private func resolvedTarget(_ target: MonefyCategoryTarget?) -> MonefyMappingRow.Target? {
        switch target {
        case .category(let id):
            guard let category = categories.first(where: { $0.id == id }) else { return nil }
            let choice = CategoryChoice(category)
            return .init(title: choice.line, iconName: choice.iconName, tone: choice.tone)
        case .uncategorized:
            return .init(title: String(localized: "feed.row.noCategory"), iconName: CategoryPaint.uncategorizedIconName, tone: nil)
        case .skip:
            return .init(title: String(localized: "monefy.target.skip"), iconName: nil, tone: nil)
        case nil:
            return nil
        }
    }

    /// Первый и последний день трат включительно (D7, E8): «5–7 окт», «21 мар 2024 – 7 окт» / «Mar 21, 2024 – Oct 7».
    /// Через границу года — две короткие даты: `range` пишет годы, только если конец не в текущем году,
    /// а выгрузке за несколько лет год начала нужен всегда.
    private var periodText: String? {
        let calendar = Calendar.current
        let formatter = AppLanguage.current.dateFormatter(calendar: calendar, now: .now)
        guard
            let period = session.plan.period,
            let start = period.lowerBound.start(in: calendar),
            let last = period.upperBound.start(in: calendar),
            let end = calendar.date(byAdding: .day, value: 1, to: last)
        else { return nil }
        guard period.lowerBound.year != period.upperBound.year else {
            return formatter.range(DateInterval(start: start, end: end))
        }
        let nb = TextSpacing.nonBreaking
        let dash = AppLanguage.current == .english ? nb + "\u{2013}" + nb : nb + "\u{2013} "
        return formatter.short(start) + dash + formatter.short(last)
    }

    /// Валюта файла не та (суммы не пересчитываются) и доходы с переводами, которые не переносятся.
    private func fileFootnote(codes: [String]) -> String? {
        var sentences: [String] = []
        if !codes.isEmpty, codes != [currencyCode] {
            sentences.append(L10n.format("monefy.currencyDiff", codes.joined(separator: ", ")))
        }
        if session.plan.notExpenseCount > 0 {
            sentences.append(String(localized: "monefy.notExpensesFooter"))
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// Почему кнопка неактивна (сколько категорий без выбора) или что будет с повторами.
    private var importFootnote: String {
        let unmapped = session.unmappedCount
        return unmapped > 0
            ? L10n.format("monefy.import.remaining", unmapped)
            : String(localized: "monefy.duplicatesFooter")
    }

    /// Число с разрядами через U+00A0.
    private func number(_ value: Int) -> String {
        TextSpacing.normalized(value.formatted(.number.locale(.app)))
    }
}

/// Строка сопоставления: имя категории Monefy и «48 трат · 1 234,50 ⃅» слева, выбор справа
/// (плашка категории и имя, «Без категории», «Не переносить» или «Выбрать»). На AX-размерах выбор — под именем.
private struct MonefyMappingRow: View {
    struct Target {
        let title: String
        /// Плашка категории; `nil` — «Не переносить» (знак запрета вместо плашки).
        let iconName: String?
        let tone: GouacheTone?
    }

    let name: String
    let meta: String
    let target: Target?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    source
                    HStack(spacing: Theme.Spacing.sm) {
                        targetLabel
                        Spacer(minLength: 0)
                        chevron
                    }
                }
            } else {
                HStack(spacing: Theme.Spacing.md) {
                    source
                        .layoutPriority(1)
                    Spacer(minLength: Theme.Spacing.sm)
                    targetLabel
                    chevron
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: SettingsLayout.rowHeight)
        .contentShape(Rectangle())
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: name)
                .typeStyle(.body)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(verbatim: meta)
                .typeStyle(.footnote)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var targetLabel: some View {
        if let target {
            HStack(spacing: Theme.Spacing.sm) {
                if let iconName = target.iconName {
                    CategoryPlaque(iconName: iconName, tone: target.tone)
                } else {
                    Image(systemName: "nosign")
                        .foregroundStyle(Theme.secondary)
                        .accessibilityHidden(true)
                }
                Text(verbatim: target.title)
                    .typeStyle(.body)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        } else {
            Text("monefy.target.none")
                .typeStyle(.body)
                .foregroundStyle(Theme.ink)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.graphic)
            .accessibilityHidden(true)
    }
}
