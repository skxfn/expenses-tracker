import SwiftUI
import ExpenseCore

/// «Привычки» (`04-stats`): 7 плиток дней недели по шкале heat (та же, что у календаря и карты года),
/// средняя за день Unbounded без знака, и два вывода словами: «Больше всего тратится **по пятницам**»,
/// «**В будни** тратится больше, чем в выходные». Мало данных — строка `stats.fewData.habits`.
struct StatsHabitsView: View {
    let state: StatsHabitsState
    let texts: StatsTexts

    @Environment(\.moneyFormatter) private var money

    var body: some View {
        if state.hasEnoughData {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                tiles
                insights
            }
        } else {
            StatsFewDataLine(key: "stats.fewData.habits")
        }
    }

    private var tiles: some View {
        HStack(spacing: StatsLayout.habitGap) {
            ForEach(state.habits.averages) { average in
                tile(average)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: texts.habitsAccessibility(state.habits)))
    }

    private func tile(_ average: StatsWeekdayAverage) -> some View {
        let level = state.scale?.level(forMinor: average.averageMinor) ?? 0
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
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
