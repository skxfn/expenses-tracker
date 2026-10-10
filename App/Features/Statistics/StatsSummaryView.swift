import SwiftUI
import ExpenseCore

/// Сводка периода над листом (`04-stats`, `05-stats-range`): «Потрачено за 8 дней», итог Unbounded 40 + знак 20,
/// фраза-сравнение (ключевая часть SF 600 графитом) и «18 трат · в среднем … в день» SF 15 secondary.
/// При раскрытой категории сводка — по ней, справа от первой строки пометка «только Продукты».
struct StatsSummaryView: View {
    let lead: String
    let summary: StatsSummary
    /// `nil` — сравнивать не с чем (`StatsTrend.incomparable`): строки нет.
    let comparison: SummaryTexts.Comparison?
    let meta: String
    /// «18 трат · в среднем 51,54 рубля в день» — для VoiceOver.
    let spokenMeta: String
    var filterMark: String?
    /// Итог для VoiceOver: «412,30 рубля».
    let spokenTotal: String

    @Environment(\.moneyFormatter) private var money

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(verbatim: lead)
                    .typeStyle(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if let filterMark {
                    StatsFilterMark(text: filterMark)
                }
            }
            AmountText(
                text: money.string(fromMinor: summary.totalMinor, style: .plain),
                value: Double(summary.totalMinor),
                size: .total,
                currency: money.currencySymbol,
                accessibilityText: spokenTotal
            )
            .minimumScaleFactor(0.6)
            .padding(.bottom, Theme.Spacing.xs)
            VStack(alignment: .leading, spacing: 2) {
                if let comparison {
                    StatsPhrase(text: comparison.text)
                        .accessibilityLabel(Text(verbatim: comparison.spoken))
                }
                Text(verbatim: meta)
                    .typeStyle(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .accessibilityLabel(Text(verbatim: spokenMeta))
            }
            .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
