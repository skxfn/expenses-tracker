import SwiftUI
import ExpenseCore

/// «Привычки» (`04-stats`): 7 плиток дней недели по шкале heat (та же, что у календаря и карты года),
/// средняя за день Unbounded без знака, и два вывода словами: «Больше всего тратится **по пятницам**»,
/// «**В будни** тратится больше, чем в выходные». Мало данных — строка `stats.fewData.habits`.
/// Касание плитки выбирает день недели (обводка графитом) и показывает под плитками стеклянную подсказку
/// «По пятницам  9 трат · 344 ⃅» с шевроном — траты этих дней списком (`onShowWeekday`); повторное касание
/// снимает выбор. VoiceOver: плитка — кнопка, открывает список сразу.
struct StatsHabitsView: View {
    let state: StatsHabitsState
    let texts: StatsTexts
    /// Траты дня недели — списком; `nil` — без действия.
    var onShowWeekday: ((Int) -> Void)?

    @State private var pin = StatsPin<Int>()
    @Environment(\.moneyFormatter) private var money
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if state.hasEnoughData {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                tiles
                if let average = selected {
                    tip(average)
                        .transition(.opacity)
                }
                insights
            }
            .animation(Motion.animation(Motion.chartTooltip, reduceMotion: reduceMotion), value: pin)
            .sensoryFeedback(Haptic.selection, trigger: pin)
            .onChange(of: state) { pin.reset() }
        } else {
            StatsFewDataLine(key: "stats.fewData.habits")
        }
    }

    private var selected: StatsWeekdayAverage? {
        pin.value.flatMap { weekday in state.habits.averages.first { $0.weekday == weekday } }
    }

    private var tiles: some View {
        HStack(spacing: StatsLayout.habitGap) {
            ForEach(state.habits.averages) { average in
                tile(average)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: texts.habitsAccessibility(state.habits)))
    }

    /// «По пятницам  9 трат · 344 ⃅ ›» — под плитками, слева.
    private func tip(_ average: StatsWeekdayAverage) -> some View {
        let action: (() -> Void)? = if let onShowWeekday, average.count > 0 { { onShowWeekday(average.weekday) } } else { nil }
        return StatsSliceTip(action: action) {
            StatsTipLine(
                title: texts.weekdayTitle(average.weekday),
                value: texts.sliceMeta(count: average.count, totalMinor: average.totalMinor)
            )
        }
        .vizDynamicTypeLimit()
    }

    private func tile(_ average: StatsWeekdayAverage) -> some View {
        let level = state.scale?.level(forMinor: average.averageMinor) ?? 0
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
        let isSelected = pin.value == average.weekday
        let canShow = onShowWeekday != nil && average.count > 0
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: texts.weekdayShort(average.weekday))
                .typeStyle(.callout)
            Spacer(minLength: Theme.Spacing.sm)
            Text(verbatim: money.string(fromMinor: average.averageMinor, style: .wholeUnits))
                .typeStyle(.amountInlineStrong)
                .minimumScaleFactor(0.5)
        }
        .lineLimit(1)
        .foregroundStyle(Theme.heatDigits(level))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: StatsLayout.habitTileHeight, alignment: .leading)
        .background(Theme.heat(level), in: shape)
        .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
        .overlay {
            if isSelected {
                shape.strokeBorder(Theme.ink, lineWidth: StatsLayout.selectionLine)
            }
        }
        .contentShape(shape)
        .onTapGesture { pin.toggle(average.weekday) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: texts.weekdayAccessibility(average)))
        .accessibilityHint(canShow ? Text("stats.slice.a11y.hint") : Text(verbatim: ""))
        .accessibilityAddTraits(canShow ? .isButton : [])
        .accessibilityAction {
            if canShow { onShowWeekday?(average.weekday) }
        }
    }

    @ViewBuilder
    private var insights: some View {
        let habits = state.habits
        if habits.peakWeekday != nil || habits.split != nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let peak = habits.peakWeekday {
                    StatsPhrase(text: texts.peakWeekday(peak))
                }
                if let split = habits.split {
                    StatsPhrase(text: texts.weekSplit(split))
                }
            }
        }
    }
}
