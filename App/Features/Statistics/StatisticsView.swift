import SwiftData
import SwiftUI
import ExpenseCore

/// Вкладка «Статистика».
struct StatisticsView: View {
    @Query private var expenses: [Expense]
    @Query private var categories: [ExpenseCategory]

    @State private var model = StatisticsModel()
    @Environment(\.moneyFormatter) private var money

    var body: some View {
        let source = StatisticsSource(expenses: expenses, categories: categories)
        Group {
            if model.hasExpenses {
                content
            } else {
                ContentUnavailableView {
                    Label("Пока нет трат", systemImage: "chart.pie")
                } description: {
                    Text("Добавьте расходы на вкладке «Расходы» — здесь появятся итоги и графики.")
                }
            }
        }
        .navigationTitle("Статистика")
        .onChange(of: source, initial: true) { _, newSource in
            model.update(source: newSource)
        }
    }

    private var content: some View {
        List {
            periodSection
            if let filterTitle = model.filterTitle {
                filterSection(title: filterTitle)
            }
            if model.isPeriodEmpty {
                Section {
                    ContentUnavailableView(
                        "Нет трат за этот период",
                        systemImage: "calendar",
                        description: Text("Выберите другой период стрелками или сменой вида.")
                    )
                }
            } else {
                summarySection
                categoriesSection
                if model.summary.count == 0 {
                    Section {
                        ContentUnavailableView(
                            "В этой категории нет трат за период",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    }
                } else {
                    chartsSections
                    topSection
                }
            }
        }
    }

    // MARK: - Период и фильтр

    private var periodSection: some View {
        Section {
            Picker("Вид периода", selection: Binding(get: { model.kind }, set: { model.select($0) })) {
                ForEach(StatsPeriodKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    model.showPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Предыдущий период")

                Spacer()
                Text(model.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Spacer()

                Button {
                    model.showNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(!model.canShowNext)
                .accessibilityLabel("Следующий период")
            }
            .buttonStyle(.borderless)

            if !model.isCurrentPeriod {
                Button("Вернуться к текущему периоду") {
                    model.showCurrent()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func filterSection(title: String) -> some View {
        Section {
            HStack {
                Label("Только «\(title)»", systemImage: "line.3.horizontal.decrease.circle.fill")
                Spacer()
                Button("Сбросить") {
                    model.clearFilter()
                }
                .buttonStyle(.borderless)
            }
        } footer: {
            Text("Фильтр действует на всю статистику, кроме разбивки по категориям.")
        }
    }

    // MARK: - Сводка

    private var summarySection: some View {
        Section("Итого") {
            VStack(alignment: .leading, spacing: 4) {
                Text(money.string(fromMinor: model.summary.totalMinor))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                changeText
                    .font(.subheadline)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)

            LabeledContent("В среднем в день", value: money.string(fromMinor: model.summary.averagePerDayMinor))
            LabeledContent("Количество трат", value: model.summary.count.formatted())
        }
    }

    private var changeText: Text {
        guard let change = model.summary.change else {
            return Text("В прошлом периоде трат не было")
                .foregroundStyle(.secondary)
        }
        let percent = change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always(includingZero: false)))
        // Рост трат — плохо (красный), снижение — хорошо (зелёный).
        let color: Color = change > 0 ? .red : (change < 0 ? .green : .secondary)
        return Text("\(percent) \(model.comparisonSuffix)")
            .foregroundStyle(color)
    }

    // MARK: - Категории

    private var categoriesSection: some View {
        Section {
            CategoryDonutChart(
                rows: model.categoryRows,
                isFiltered: model.filter != .all,
                totalText: money.string(fromMinor: model.periodTotalMinor)
            )
            ForEach(model.categoryRows) { row in
                Button {
                    model.toggleFilter(row.filter)
                } label: {
                    categoryRow(row)
                }
                .tint(.primary)
                .accessibilityAddTraits(row.isSelected ? .isSelected : [])
                .accessibilityHint(row.isSelected ? "Снять фильтр" : "Показать статистику только по этой категории")
            }
        } header: {
            Text("По категориям")
        } footer: {
            Text("Нажмите на категорию, чтобы отфильтровать по ней всю статистику.")
        }
    }

    private func categoryRow(_ row: CategoryShareRow) -> some View {
        HStack(spacing: 12) {
            CategoryIconView(row.appearance, diameter: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.appearance.name)
                    .lineLimit(2)
                Text(row.share.formatted(.percent.precision(.fractionLength(0...1))))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(money.string(fromMinor: row.totalMinor))
                .monospacedDigit()
                .layoutPriority(1)
            if row.isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Графики

    @ViewBuilder
    private var chartsSections: some View {
        Section("По времени") {
            TimeSeriesChart(series: model.timeSeries, kind: model.kind)
        }
        if let cumulative = model.cumulative {
            Section("Накопительно") {
                CumulativeChart(
                    comparison: cumulative,
                    currentLabel: model.currentSeriesLabel,
                    previousLabel: model.previousSeriesLabel
                )
            }
        }
        if model.showsWeekdays {
            Section("В среднем по дням недели") {
                WeekdayChart(rows: model.weekdays)
            }
        }
    }

    // MARK: - Топ

    private var topSection: some View {
        Section("Самые крупные траты") {
            ForEach(model.topExpenses) { row in
                HStack(spacing: 12) {
                    CategoryIconView(row.appearance, diameter: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.note.isEmpty ? row.appearance.name : row.note)
                            .lineLimit(2)
                        Text(row.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(money.string(fromMinor: row.amountMinor))
                        .monospacedDigit()
                        .layoutPriority(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview {
    NavigationStack {
        StatisticsView()
    }
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
