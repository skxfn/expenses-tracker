import Charts
import SwiftUI
import ExpenseCore

/// «Темп» (`04-stats`): «≈ 1 600 ⃅» Unbounded 28, «к 31 октября при текущем темпе», легенда
/// «октябрь — сентябрь — прогноз» и накопительные кривые: текущая ink, прошлая graphic, прогноз — точками
/// до конца периода. У прошедшего периода вместо прогноза — итог («итог за сентябрь»).
/// Мало данных (`StatsThresholds`) — строка `stats.fewData.pace` вместо графика.
/// Касание и ведение пальцем по графику выбирают день: вертикаль, точки на обеих кривых и стеклянная подсказка
/// в свободном верхнем углу поля — накопленное к этому дню сейчас и в прошлом периоде и разница; выбор
/// закрепляется, шеврон подсказки открывает траты дня (`onShowDay`). VoiceOver — adjustable по дням.
struct StatsPaceView: View {
    let pace: StatsPaceState
    let period: StatsPeriod
    let texts: StatsTexts
    /// Траты дня — списком; `nil` — без действия.
    var onShowDay: ((Date) -> Void)?

    @State private var selectedX: Double?
    /// Выбранный день (номер с 1): остаётся и после того, как палец поднят.
    @State private var pin = StatsPin<Int>()
    @Environment(\.moneyFormatter) private var money
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if pace.hasEnoughData {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    headline
                    Text(verbatim: texts.paceNote(period, hasForecast: pace.forecast != nil))
                        .typeStyle(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }
                legend
                chart
            }
        } else {
            StatsFewDataLine(key: "stats.fewData.pace")
        }
    }

    // MARK: Итог или прогноз

    /// Unbounded 28 + знак 14 (макет `04-stats`): мельче итога периода над листом (40), чтобы с ним не спорить.
    @ViewBuilder
    private var headline: some View {
        if let forecast = pace.forecast {
            AmountText(
                text: texts.approximate(forecast.roundedMinor),
                value: Double(forecast.roundedMinor),
                size: .ringTotal,
                currency: money.currencySymbol,
                accessibilityText: texts.shared.spoken(forecast.roundedMinor)
            )
        } else {
            AmountText(
                text: money.string(fromMinor: pace.totalMinor, style: .plain),
                value: Double(pace.totalMinor),
                size: .ringTotal,
                currency: money.currencySymbol,
                accessibilityText: texts.shared.spoken(pace.totalMinor)
            )
        }
    }

    // MARK: Легенда

    private var legend: some View {
        HStack(spacing: Theme.Spacing.lg) {
            legendItem(texts.periodName(period, month: .abbreviated)) {
                Capsule().fill(Theme.ink)
                    .frame(width: StatsLayout.legendSwatch.width, height: StatsLayout.legendSwatch.height)
            }
            legendItem(texts.previousName(period)) {
                Capsule().fill(Theme.graphic)
                    .frame(width: StatsLayout.legendSwatch.width, height: StatsLayout.legendSwatch.height)
            }
            if pace.forecast != nil {
                legendItem(String(localized: "stats.pace.legend.forecast")) {
                    HStack(spacing: StatsLayout.legendSwatch.height) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Theme.ink)
                                .frame(width: StatsLayout.legendSwatch.height, height: StatsLayout.legendSwatch.height)
                        }
                    }
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        // Легенда графика — не крупнее AX1, как его подписи: иначе «окт…, сент…».
        .vizDynamicTypeLimit()
        .accessibilityHidden(true)
    }

    private func legendItem(_ title: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            swatch()
            Text(verbatim: title)
                .typeStyle(.footnote)
                .foregroundStyle(Theme.secondary)
        }
    }

    // MARK: График

    private var current: [StatsCumulativePoint] { pace.comparison.current }
    private var previous: [StatsCumulativePoint] { pace.comparison.previous }
    /// Длина оси: дни периода (или прошлого, если он длиннее).
    private var dayCount: Int { max(pace.dayCount, previous.count, 2) }

    private var chart: some View {
        Chart {
            ForEach(ticks, id: \.self) { tick in
                RuleMark(xStart: .value("x", 1.0), xEnd: .value("x", Double(dayCount)), y: .value("y", StatsBarsChart.chartValue(tick)))
                    .foregroundStyle(Theme.separator)
                    .lineStyle(StrokeStyle(lineWidth: Theme.Size.hairline))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(verbatim: money.string(fromMinor: tick, style: .wholeUnits))
                            .typeStyle(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
            }
            RuleMark(xStart: .value("x", 1.0), xEnd: .value("x", Double(dayCount)), y: .value("y", 0.0))
                .foregroundStyle(Theme.graphic)
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(previous) { point in
                line(point, series: "previous", color: Theme.graphic, style: Self.previousStyle)
            }
            ForEach(current) { point in
                line(point, series: "current", color: Theme.ink, style: Self.currentStyle)
            }
            if let forecast = pace.forecast, let today = current.last {
                line(today, series: "forecast", color: Theme.ink, style: Self.forecastStyle)
                LineMark(
                    x: .value("x", Double(pace.dayCount)),
                    y: .value("y", StatsBarsChart.chartValue(forecast.projectedMinor)),
                    series: .value("series", "forecast")
                )
                .foregroundStyle(Theme.ink)
                .lineStyle(Self.forecastStyle)
            }
            if let end = previous.last {
                point(end.dayNumber, end.cumulativeMinor, color: Theme.graphic, size: StatsLayout.pacePoint * 0.8)
            }
            if pace.forecast != nil, let today = current.last {
                point(today.dayNumber, today.cumulativeMinor, color: Theme.ink, size: StatsLayout.pacePoint)
            }
            endPoint
            if let day = shownDay {
                selectionMarks(day)
            }
            // Подписи оси — аннотациями на нулевой линии: подпись последнего дня ось Swift Charts не рисует.
            ForEach(axisLabels, id: \.day) { label in
                PointMark(x: .value("x", Double(label.day)), y: .value("y", 0.0))
                    .symbolSize(0)
                    .annotation(
                        position: .bottom,
                        alignment: .center,
                        spacing: Theme.Spacing.sm,
                        overflowResolution: .init(x: .disabled, y: .disabled)
                    ) {
                        Text(verbatim: label.text)
                            .typeStyle(label.isCurrent ? .footnoteStrong : .footnote)
                            .foregroundStyle(label.isCurrent ? Theme.ink : Theme.secondary)
                            .fixedSize()
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(
            domain: 1...Double(dayCount) + Self.domainSlack,
            range: .plotDimension(endPadding: dynamicTypeSize.chartScaled(StatsLayout.paceTrailingSpace, relativeTo: .subheadline))
        )
        .chartYScale(domain: 0...yMax)
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .chartXSelection(value: $selectedX)
        // Подсказка — слоем в верхнем левом углу поля: накопительные кривые растут вправо вверх, угол свободен.
        // В аннотациях Swift Charts стекло не рисуется (AGENTS.md).
        .chartOverlay(alignment: .topLeading) { proxy in
            GeometryReader { geometry in
                if let day = shownDay.flatMap(pace.comparison.day), let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    tip(day)
                        .fixedSize()
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        // Подписи — не крупнее AX1, место под ними растёт вместе с ними: иначе подписи у концов кривых режутся краем.
        .vizDynamicTypeLimit()
        .frame(height: StatsLayout.paceHeight)
        .padding(.bottom, dynamicTypeSize.chartScaled(StatsLayout.paceAxisSpace, relativeTo: .footnote))
        .animation(reduceMotion ? nil : Motion.chartTooltip, value: shownDay)
        .sensoryFeedback(Haptic.selection, trigger: selectedDay)
        .onChange(of: selectedDay) { old, new in pin.track(from: old, to: new) }
        .onChange(of: pace) { pin.reset() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: texts.paceAccessibility(pace, period: period)))
        .accessibilityValue(Text(verbatim: shownDay.flatMap(pace.comparison.day).map(texts.paceDayAccessibility) ?? ""))
        .accessibilityHint(selectedSlice != nil ? Text("stats.slice.a11y.hint") : Text(verbatim: ""))
        .accessibilityAdjustableAction(adjust)
        .accessibilityAction {
            if let date = selectedSlice { onShowDay?(date) }
        }
    }

    // MARK: Выбор дня

    /// День под пальцем, иначе закреплённый; только дни текущей кривой (с 1).
    private var shownDay: Int? { selectedDay ?? pin.value }

    /// День под пальцем: ближайший к точке касания, в пределах текущей кривой.
    private var selectedDay: Int? {
        guard let selectedX, !current.isEmpty else { return nil }
        return min(max(Int(selectedX.rounded()), 1), current.count)
    }

    /// Дата закреплённого дня, если в сам день были траты: есть что открыть списком.
    private var selectedSlice: Date? {
        guard onShowDay != nil, let day = shownDay.flatMap(pace.comparison.day), day.dayMinor > 0 else { return nil }
        return day.current.date
    }

    /// VoiceOver: смахивание вверх / вниз — следующий / предыдущий день.
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        guard !current.isEmpty else { return }
        let day = pin.value ?? (direction == .increment ? 0 : current.count + 1)
        switch direction {
        case .increment: pin.select(min(day + 1, current.count))
        case .decrement: pin.select(max(day - 1, 1))
        @unknown default: break
        }
    }

    /// Вертикаль дня и точки на обеих кривых.
    @ChartContentBuilder
    private func selectionMarks(_ dayNumber: Int) -> some ChartContent {
        RuleMark(x: .value("x", Double(dayNumber)), yStart: .value("y", 0.0), yEnd: .value("y", yMax))
            .foregroundStyle(Theme.graphic)
            .lineStyle(StrokeStyle(lineWidth: 1))
        if let day = pace.comparison.day(dayNumber) {
            if let previous = day.previous {
                point(dayNumber, previous.cumulativeMinor, color: Theme.graphic, size: StatsLayout.pacePoint * 0.8)
            }
            point(dayNumber, day.current.cumulativeMinor, color: Theme.ink, size: StatsLayout.pacePoint)
        }
    }

    /// «к 12 окт  642,10 ⃅» графитом, «к 12 сен  580,00 ⃅» secondary и «на 62,10 ⃅ больше».
    private func tip(_ day: StatsPaceDay) -> some View {
        StatsSliceTip(action: selectedSlice.map { date in { onShowDay?(date) } }) {
            VStack(alignment: .leading, spacing: 2) {
                StatsTipLine(
                    title: texts.paceTipDay(day.current.date),
                    value: money.string(fromMinor: day.current.cumulativeMinor)
                )
                if let previous = day.previous {
                    StatsTipLine(
                        title: texts.paceTipDay(previous.date),
                        value: money.string(fromMinor: previous.cumulativeMinor),
                        valueColor: Theme.secondary
                    )
                }
                if let difference = texts.paceTipDifference(day) {
                    StatsPhrase(text: difference)
                        .lineLimit(1)
                }
            }
        }
    }

    private func line(_ point: StatsCumulativePoint, series: String, color: Color, style: StrokeStyle) -> some ChartContent {
        LineMark(
            x: .value("x", Double(point.dayNumber)),
            y: .value("y", StatsBarsChart.chartValue(point.cumulativeMinor)),
            series: .value("series", series)
        )
        .foregroundStyle(color)
        .lineStyle(style)
    }

    private func point(_ day: Int, _ minor: Int64, color: Color, size: CGFloat) -> some ChartContent {
        PointMark(x: .value("x", Double(day)), y: .value("y", StatsBarsChart.chartValue(minor)))
            .symbol {
                Circle().fill(color).frame(width: size, height: size)
            }
    }

    /// Конец прогноза (открытый круг) или конец текущей кривой у прошедшего периода — с подписью справа:
    /// «≈ 1 600» и итог прошлого периода «1 580» под ним.
    @ChartContentBuilder
    private var endPoint: some ChartContent {
        let end: (day: Int, minor: Int64, label: String)? = if let forecast = pace.forecast {
            (pace.dayCount, forecast.projectedMinor, texts.approximate(forecast.roundedMinor))
        } else if let last = current.last {
            (last.dayNumber, last.cumulativeMinor, money.string(fromMinor: last.cumulativeMinor, style: .wholeUnits))
        } else {
            nil
        }
        if let end {
            PointMark(x: .value("x", Double(end.day)), y: .value("y", StatsBarsChart.chartValue(end.minor)))
                .symbol {
                    Circle()
                        .strokeBorder(Theme.ink, lineWidth: 2)
                        .background(Circle().fill(Theme.surface))
                        .frame(width: StatsLayout.pacePoint + 2, height: StatsLayout.pacePoint + 2)
                }
                .annotation(position: .trailing, alignment: .leading, spacing: Theme.Spacing.xs) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: end.label)
                            .typeStyle(.callout)
                            .foregroundStyle(Theme.ink)
                        if let previousTotal = previous.last?.cumulativeMinor, previousTotal > 0 {
                            Text(verbatim: money.string(fromMinor: previousTotal, style: .wholeUnits))
                                .typeStyle(.subheadline)
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
        }
    }

    /// Запас домена за последним днём: точка ровно на границе домена у Swift Charts теряется.
    private static let domainSlack = 0.01

    private static let currentStyle = StrokeStyle(lineWidth: StatsLayout.paceCurrentLine, lineCap: .round, lineJoin: .round)
    private static let previousStyle = StrokeStyle(lineWidth: StatsLayout.pacePreviousLine, lineCap: .round, lineJoin: .round)
    /// Точки: штрих почти нулевой длины с круглым концом.
    private static let forecastStyle = StrokeStyle(
        lineWidth: StatsLayout.paceForecastLine, lineCap: .round, dash: [0.01, 2 * StatsLayout.paceForecastLine]
    )

    // MARK: Шкалы

    private var maxMinor: Int64 {
        [pace.forecast?.projectedMinor, previous.last?.cumulativeMinor, current.last?.cumulativeMinor]
            .compactMap { $0 }
            .max() ?? 0
    }

    /// Деления 500 · 1 000 · 1 500 — не выше максимума (макет).
    private var ticks: [Int64] { StatsChartAxes.valueTicks(upTo: maxMinor) }

    /// Запас сверху под подпись верхнего деления и конец кривой.
    private var yMax: Double { max(StatsBarsChart.chartValue(maxMinor) * 1.08, 1) }

    /// «1, 8, 15, 22, 31» и сегодня; неделя — дни недели; год — «Янв, Апр, Июл, Окт».
    private var axisLabels: [StatsTexts.AxisDay] {
        texts.paceAxisLabels(
            period,
            dayCount: dayCount,
            lastIndex: pace.dayCount - 1,
            todayIndex: pace.forecast != nil ? current.count - 1 : nil
        )
    }
}
