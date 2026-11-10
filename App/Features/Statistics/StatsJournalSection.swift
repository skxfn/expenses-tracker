import SwiftUI
import ExpenseCore

/// Журнал выбранной категории (просьба владельца: в детализации первым делом — когда на неё тратилось):
/// заголовок «Траты» с пометкой «только Кафе», начало ленты её трат за период по дням — стеклянные заголовки дней
/// и строки ленты (тап — правка, действия VoiceOver «Удалить» и «Повторить сегодня»), под ними «Ещё 40 трат ›»:
/// весь журнал списком со свайпами (`StatsSliceListView`). Стоит сразу под «Категориями», над графиками.
struct StatsJournalSection: View {
    let journal: StatsJournalState
    let filterMark: String?
    /// Заголовки дней — как в ленте вкладки «Траты».
    let feed: HomeTexts
    let onShowAll: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            StatsSectionHeader(title: Text("stats.journal.heading"), filterMark: filterMark)
            VStack(alignment: .leading, spacing: StatsLayout.journalDaySpacing) {
                ForEach(journal.days) { day in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        FeedDayHeader(
                            title: feed.dayTitle(day.day),
                            totalMinor: day.totalMinor,
                            accessibilityText: feed.dayAccessibility(day.day, totalMinor: day.totalMinor)
                        )
                        VStack(spacing: 0) {
                            ForEach(day.rows) { row in
                                ExpenseFeedRow(data: row) { errorMessage = $0 }
                            }
                        }
                    }
                }
            }
            if journal.hiddenCount > 0 {
                Button(action: onShowAll) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(verbatim: L10n.format("stats.journal.more", journal.hiddenCount))
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .fontWeight(.semibold)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.glassCapsule(.glass, height: Theme.Size.chip, expands: false))
            }
        }
        .errorAlert($errorMessage)
    }
}
