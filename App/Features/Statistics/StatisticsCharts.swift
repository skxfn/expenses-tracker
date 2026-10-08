import Charts
import SwiftUI
import ExpenseCore

/// Перевод minor-единиц в число для Swift Charts. Только для отображения: расчёты — в `Int64`.
private func chartAmount(_ minor: Int64) -> Double {
    Double(minor) / Double(Money.minorUnitsPerMajor)
}

/// Подписи оси сумм: «1,2 тыс.» вместо «1200,00 Br», чтобы ось не съедала ширину.
private func compactAmountAxis() -> some AxisContent {
    AxisMarks { value in
        AxisGridLine()
        AxisValueLabel {
            if let amount = value.as(Double.self) {
                Text(amount, format: .number.notation(.compactName))
            }
        }
    }
}

// MARK: - Категории

/// Кольцевая диаграмма долей категорий. При фильтре невыбранные категории приглушаются.
struct CategoryDonutChart: View {
    let rows: [CategoryShareRow]
    let isFiltered: Bool
    let totalText: String

    var body: some View {
        Chart(rows) { row in
            SectorMark(
                angle: .value("Сумма", chartAmount(row.totalMinor)),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(Color(hex: row.appearance.colorHex))
            .opacity(!isFiltered || row.isSelected ? 1 : 0.3)
            .accessibilityLabel(row.appearance.name)
            .accessibilityValue(row.share.formatted(.percent.precision(.fractionLength(0...1))))
        }
        .chartLegend(.hidden)
        .frame(height: 220)
        .overlay {
            VStack(spacing: 2) {
                Text("Всего")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(totalText)
                    .font(.headline)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .frame(maxWidth: 120)
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Траты по времени

/// Столбцы трат по часам, дням или месяцам периода.
struct TimeSeriesChart: View {
    let series: StatsTimeSeries
    let kind: StatsPeriodKind

    var body: some View {
        Chart(series.buckets) { bucket in
            BarMark(
                x: .value("Время", bucket.interval.start, unit: series.step.calendarComponent),
                y: .value("Сумма", chartAmount(bucket.totalMinor))
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: axisStride.component, count: axisStride.count)) { _ in
                AxisGridLine()
                AxisValueLabel(format: axisFormat, centered: true)
            }
        }
        .chartYAxis { compactAmountAxis() }
        .frame(height: 200)
        .padding(.vertical, 8)
    }

    private var axisStride: (component: Calendar.Component, count: Int) {
        switch kind {
        case .day: (.hour, 6)
        case .week: (.day, 1)
        case .month: (.day, 7)
        case .year: (.month, 1)
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch kind {
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.day()
        case .year: .dateTime.month(.narrow)
        }
    }
}

// MARK: - Накопительно

/// Накопительные суммы текущего и прошлого периода по номеру дня.
struct CumulativeChart: View {
    let comparison: StatsCumulativeComparison
    let currentLabel: String
    let previousLabel: String

    var body: some View {
        Chart {
            ForEach(comparison.previous) { point in
                LineMark(
                    x: .value("День", point.dayNumber),
                    y: .value("Сумма", chartAmount(point.cumulativeMinor))
                )
                .foregroundStyle(by: .value("Период", previousLabel))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            ForEach(comparison.current) { point in
                LineMark(
                    x: .value("День", point.dayNumber),
                    y: .value("Сумма", chartAmount(point.cumulativeMinor))
                )
                .foregroundStyle(by: .value("Период", currentLabel))
                .lineStyle(StrokeStyle(lineWidth: 3))
            }
        }
        .chartForegroundStyleScale([currentLabel: Color.accentColor, previousLabel: Color.gray])
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxis { compactAmountAxis() }
        .frame(height: 220)
        .padding(.vertical, 8)
    }
}

// MARK: - Дни недели

/// Средняя трата в каждый день недели.
struct WeekdayChart: View {
    let rows: [WeekdayRow]

    var body: some View {
        Chart(rows) { row in
            BarMark(
                x: .value("День недели", row.label),
                y: .value("В среднем", chartAmount(row.averageMinor))
            )
            .foregroundStyle(Color.accentColor.gradient)
        }
        .chartYAxis { compactAmountAxis() }
        .frame(height: 180)
        .padding(.vertical, 8)
    }
}
