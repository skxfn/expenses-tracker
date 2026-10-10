import Charts
import SwiftUI
import ExpenseCore

/// «По дням» (`04-stats`), «По часам» (вид «День», только сегодня) и «По месяцам» (вид «Год»): столбики сумм.
/// Прошлые — graphic, подсвеченный (под пальцем, иначе сегодняшний) — ink, будущие — чёрточки separator.
/// Пунктир средней с подписью «в среднем 51,54», редкие подписи оси (1, 8, 15, 22, 29 и сегодня — полужирным,
/// INTEGRATION §6) и скраббинг `chartXSelection` со стеклянной подсказкой «Сегодня 57,20 ⃅» (`stats.days.tip`).
struct StatsBarsChart: View {
    let series: StatsTimeSeries
    let period: StatsPeriod
    let now: Date
    /// Линия средней; `nil` или 0 — без неё.
    var averageMinor: Int64?
    let texts: StatsTexts

    @State private var selectedDate: Date?
    @State private var tooltipWidth: CGFloat = 0
    @Environment(\.moneyFormatter) private var money
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var buckets: [StatsTimeBucket] { series.buckets }
    private var unit: Calendar.Component { series.step.calendarComponent }

    var body: some View {
        Chart {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                if isFuture(bucket) {
                    RectangleMark(
                        x: .value("x", bucket.interval.start, unit: unit),
                        y: .value("y", 0.0),
                        width: barWidth,
                        height: .fixed(StatsLayout.futureDashHeight)
                    )
                    .foregroundStyle(Theme.separator)
                    .cornerRadius(StatsLayout.futureDashHeight / 2)
                    .accessibilityHidden(true)
                } else {
                    BarMark(
                        x: .value("x", bucket.interval.start, unit: unit),
                        y: .value("y", Self.chartValue(bucket.totalMinor)),
                        width: barWidth
                    )
                    .foregroundStyle(index == shownIndex ? Theme.ink : Theme.graphic)
                    .cornerRadius(StatsLayout.barCorner)
                    .accessibilityLabel(Text(verbatim: texts.bucketAccessibility(bucket, step: series.step)))
                }
            }
            if let averageMinor, averageMinor > 0 {
                RuleMark(y: .value("y", Self.chartValue(averageMinor)))
                    .foregroundStyle(Theme.graphic)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text(verbatim: texts.averageLabel(averageMinor))
                            .typeStyle(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
                    .accessibilityHidden(true)
            }
            if let shownIndex {
                let bucket = buckets[shownIndex]
                RuleMark(
                    x: .value("x", bucket.interval.start, unit: unit),
                    yStart: .value("y", Self.chartValue(bucket.totalMinor)),
                    yEnd: .value("y", yMax)
                )
                .foregroundStyle(Theme.graphic)
                .lineStyle(StrokeStyle(lineWidth: 1))
                .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: period.interval.start...period.interval.end)
        .chartYScale(domain: 0...yMax)
        .chartYAxis(.hidden)
        .chartXAxis { xAxis }
        .chartXSelection(value: $selectedDate)
        // Подсказка — слоем поверх графика, а не аннотацией: в аннотациях Swift Charts стекло не рисуется.
        .chartOverlay(alignment: .topLeading) { proxy in
            GeometryReader { geometry in
                if let shownIndex, let plotFrame = proxy.plotFrame {
                    let bucket = buckets[shownIndex]
                    let middle = bucket.interval.start.addingTimeInterval(bucket.interval.duration / 2)
                    let x = (proxy.position(forX: middle) ?? 0) + geometry[plotFrame].minX
                    tooltip(bucket)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tooltipWidth = $0 }
                        .offset(
                            x: min(max(x - tooltipWidth / 2, 0), max(geometry.size.width - tooltipWidth, 0)),
                            y: -StatsLayout.tooltipSpace
                        )
                }
            }
        }
        .frame(height: StatsLayout.barsHeight)
        .padding(.top, StatsLayout.tooltipSpace)
        // При Reduce Motion подсказка переставляется без движения (§3.6).
        .animation(reduceMotion ? nil : Motion.chartTooltip, value: shownIndex)
        .sensoryFeedback(Haptic.selection, trigger: selectedIndex)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: texts.seriesAccessibility(period, step: series.step)))
    }

    // MARK: Подсказка

    /// Стеклянная подсказка дня над полем: «Сегодня» secondary + сумма графитом, обе SF 15/600.
    private func tooltip(_ bucket: StatsTimeBucket) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(verbatim: texts.bucketTitle(bucket, step: series.step))
                .foregroundStyle(Theme.secondary)
            Text(verbatim: money.string(fromMinor: bucket.totalMinor))
                .foregroundStyle(Theme.ink)
        }
        .typeStyle(.callout)
        .lineLimit(1)
        .padding(.horizontal, Theme.Spacing.md + Theme.Spacing.xs)
        .frame(minHeight: Theme.Size.dayHeader)
        .glass(.inContent)
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Ось

    private var xAxis: some AxisContent {
        let labels = axisLabels
        return AxisMarks(values: labels.map(\.date)) { value in
            AxisValueLabel {
                if let date = value.as(Date.self), let label = labels.first(where: { abs($0.date.timeIntervalSince(date)) < 1 }) {
                    Text(verbatim: label.text)
                        .typeStyle(label.isCurrent ? .footnoteStrong : .footnote)
                        .foregroundStyle(label.isCurrent ? Theme.ink : Theme.secondary)
                }
            }
        }
    }

    private struct AxisLabel {
        /// Середина отрезка: подпись стоит под столбиком.
        let date: Date
        let text: String
        let isCurrent: Bool
    }

    /// Каждый 7-й день (у часов — 6-й, у месяцев — 3-й) и текущий; неделя и короткий период — все.
    private var axisLabels: [AxisLabel] {
        let step = switch series.step {
        case .hour: 6
        case .month: 3
        case .day, .week: 7
        }
        let pinned = currentIndex.map { [$0] } ?? []
        let gap = series.step == .month ? 2 : 3
        return StatsChartAxes.labeledIndices(count: buckets.count, step: step, pinned: pinned, minimumGap: gap).map { index in
            let bucket = buckets[index]
            return AxisLabel(
                date: bucket.interval.start.addingTimeInterval(bucket.interval.duration / 2),
                text: texts.axisLabel(bucket, step: series.step, period: period),
                isCurrent: index == currentIndex
            )
        }
    }

    // MARK: Состояние

    /// Отрезок с сегодняшним моментом.
    private var currentIndex: Int? {
        buckets.firstIndex { $0.interval.start <= now && now < $0.interval.end }
    }

    /// Отрезок под пальцем; будущие без трат не выбираются.
    private var selectedIndex: Int? {
        guard let selectedDate else { return nil }
        let index = buckets.firstIndex { $0.interval.start <= selectedDate && selectedDate < $0.interval.end }
        return index.flatMap { isFuture(buckets[$0]) ? nil : $0 }
    }

    /// Подсвеченный отрезок: под пальцем, иначе сегодняшний.
    private var shownIndex: Int? { selectedIndex ?? currentIndex }

    /// Ширина столбика: доля ширины дня (месяц, часы), а у недели, года и коротких периодов — не шире
    /// `barMaxWidth`, иначе 3–12 столбиков становятся плитами.
    private var barWidth: MarkDimension {
        buckets.count >= StatsLayout.barRatioMinimumCount
            ? .ratio(StatsLayout.barWidthRatio)
            : .fixed(StatsLayout.barMaxWidth)
    }

    /// Будущий день без трат — чёрточка вместо столбика.
    private func isFuture(_ bucket: StatsTimeBucket) -> Bool {
        bucket.interval.start > now && bucket.totalMinor == 0
    }

    /// Верх шкалы: самый высокий столбик или средняя.
    private var yMax: Double {
        let top = max(buckets.map(\.totalMinor).max() ?? 0, averageMinor ?? 0)
        return max(Self.chartValue(top), 1)
    }

    /// Сумма для Swift Charts — только для отображения, расчёты в `Int64`.
    static func chartValue(_ minor: Int64) -> Double {
        Double(minor) / Double(Money.minorUnitsPerMajor)
    }
}
