#if DEBUG
import SwiftUI
import ExpenseCore

/// Сценарии `-debugPeriod` для проверки шапки периода без касаний.
enum PeriodDebugScenario: String {
    /// Текущий месяц (`-debugPeriod YES`).
    case month
    case day, week, year
    /// Свой период: 3 дня, кончающиеся вчера, — как «5–7 окт» в макете `03-home-range`.
    case range
    /// Прошлый месяц: виден чип «Сегодня».
    case past
    /// Сентябрь прошлого года — самый длинный заголовок: месяц, год и чип «Сегодня».
    case pastYear
    /// Сразу открыт шит «Период».
    case sheet
}

/// DEBUG-экран: шапка периода и сегмент над пустым бумажным листом; на листе — состояние `PeriodSelection`.
/// На вкладке «Траты» — вид `.home`, на «Статистике» — `.statistics`.
struct PeriodDebugScreen: View {
    let style: PeriodHeader.Style
    @State private var selection: PeriodSelection

    private static let auraTones: [GouacheTone] = [.shalfey, .abrikos]

    init(scenario: PeriodDebugScenario, style: PeriodHeader.Style) {
        self.style = style
        let selection = PeriodSelection(kind: Self.kind(for: scenario))
        switch scenario {
        case .range:
            let today = selection.today
            let first = selection.calendar.date(byAdding: .day, value: -3, to: today) ?? today
            let last = selection.calendar.date(byAdding: .day, value: -1, to: today) ?? today
            selection.applyCustom(from: first, through: last)
        case .past:
            selection.showPrevious()
        case .pastYear:
            let year = selection.calendar.component(.year, from: selection.now) - 1
            let september = selection.calendar.date(from: DateComponents(year: year, month: 9, day: 15)) ?? selection.now
            selection.apply(.current(.month, now: september, calendar: selection.calendar))
        case .sheet:
            selection.presentPicker()
        case .month, .day, .week, .year:
            break
        }
        _selection = State(initialValue: selection)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.md) {
                PeriodHeader(selection: selection, style: style, auraTones: Self.auraTones)
                PeriodSegment(selection: selection)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.sm)

            state
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Theme.Spacing.xl)
                .paperSheetBackground()
                .padding(.top, Theme.Spacing.xs)
        }
        .background(AuraBackground(tones: Self.auraTones).ignoresSafeArea())
    }

    private var state: some View {
        let interval = selection.period.interval
        let format = Date.ISO8601FormatStyle(timeZone: selection.calendar.timeZone).year().month().day()
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(verbatim: "\(selection.mode) · \(selection.dayCount) дн.")
            Text(verbatim: "[\(interval.start.formatted(format)), \(interval.end.formatted(format)))")
            Text(verbatim: "isCurrent \(selection.isCurrent) · canShowNext \(selection.canShowNext)")
            Text(verbatim: "custom \(selection.customInterval.map { $0.start.formatted(format) } ?? "—")")
        }
        .typeStyle(.footnote)
        .foregroundStyle(Theme.secondary)
    }

    private static func kind(for scenario: PeriodDebugScenario) -> StatsPeriodKind {
        switch scenario {
        case .day: .day
        case .week: .week
        case .year: .year
        case .month, .range, .past, .pastYear, .sheet: .month
        }
    }
}
#endif
