import SwiftData
import SwiftUI
import ExpenseCore

/// Шит «Период» (макет `10-period`): готовые периоды стеклянными чипами, строка «С … → По … · N дней ≈ сумма»,
/// календарь на листе и prominent «Показать 24 сен – 8 окт». Чип применяется сразу; выбор в календаре —
/// по «Показать». Сумма — по тратам диапазона, округлённая до целых (без тех, что ждут удаления).
struct PeriodSheet: View {
    let selection: PeriodSelection
    var auraTones: [GouacheTone] = []

    @Query(sort: \Expense.date) private var expenses: [Expense]
    @Environment(PendingDeletion.self) private var pendingDeletion
    @Environment(\.moneyFormatter) private var money
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PeriodRangeDraft

    init(selection: PeriodSelection, auraTones: [GouacheTone] = []) {
        self.selection = selection
        self.auraTones = auraTones
        _draft = State(initialValue: PeriodRangeDraft(
            period: selection.period,
            today: selection.today,
            calendar: selection.calendar
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                presets
                rangeLine
                    .padding(.horizontal, Theme.Spacing.screen)
                PeriodRangeCalendar(
                    calendar: selection.calendar,
                    today: selection.today,
                    firstMonth: firstMonth,
                    draft: $draft
                )
            }
            .padding(.top, Theme.Spacing.sm)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                applyButton
            }
            .sheetHeader("period.title", onClose: { dismiss() })
            .sensoryFeedback(Haptic.selection, trigger: draft)
        }
        .presentationDetents([.custom(PeriodSheetDetent.self)])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            AuraBackground(tones: auraTones, base: Theme.canvasElevated)
        }
    }

    // MARK: - Готовые периоды

    private var presets: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(PeriodPreset.allCases) { preset in
                        presetChip(preset)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("period.presets.a11y")
    }

    private func presetChip(_ preset: PeriodPreset) -> some View {
        let period = preset.period(today: selection.today, earliestExpense: earliestExpense, calendar: selection.calendar)
        return Button {
            guard let period else { return }
            selection.apply(period)
            dismiss()
        } label: {
            Text(preset.titleKey)
                .typeStyle(.callout)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: Theme.Size.chip)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(.key)
        .disabled(period == nil)
        .opacity(period == nil ? Theme.disabledArrowOpacity : 1)
    }

    // MARK: - Строка диапазона

    private var rangeLine: some View {
        let total = rangeTotalMinor
        return ViewThatFits(in: .horizontal) {
            rangeLine(meta: fullMeta(total: total))
                .fixedSize(horizontal: true, vertical: false)
            rangeLine(meta: shortMeta)
                .minimumScaleFactor(0.7)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rangeAccessibility(total: total)))
    }

    private func rangeLine(meta: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(verbatim: L10n.format("period.range.from", formatter.short(draft.start ?? selection.today)))
                .typeStyle(.headline)
                .foregroundStyle(Theme.ink)
            Image(systemName: "arrow.right")
                .font(.system(size: TypeStyle.amountInline.size, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            Text(verbatim: L10n.format("period.range.to", draft.end.map(formatter.short) ?? "…"))
                .typeStyle(.headline)
                .foregroundStyle(draft.isAwaitingEnd ? Theme.secondary : Theme.ink)
            Text(verbatim: meta)
                .typeStyle(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
    }

    /// Сумма диапазона, округлённая до целых; `nil` — конец ещё не выбран (`period.range.single`).
    private var rangeTotalMinor: Int64? {
        guard !draft.isAwaitingEnd, let interval else { return nil }
        return Money.roundedToWholeUnits(totalMinor(in: interval))
    }

    /// «· 15 дней ≈ 742 Br»; пока выбран только первый день — «· выберите конец».
    private func fullMeta(total: Int64?) -> String {
        guard let total else { return String(localized: "period.range.single") }
        return L10n.format("period.range.meta", dayCount, money.string(fromMinor: total, style: .phrase))
    }

    /// VoiceOver — одной фразой из тех же строк: «С 1 октября по 10 октября, 10 дней ≈ 545 рублей»
    /// (en: «October 1 to October 10, …»). Даты полностью, сумма словом (`a11y.money`), без «·».
    private func rangeAccessibility(total: Int64?) -> String {
        let start = L10n.format("period.range.from", formatter.dayMonth(draft.start ?? selection.today))
        guard let total, let end = draft.end else {
            return start + ", " + Self.spokenMeta(String(localized: "period.range.single"))
        }
        let range = start + " " + String(localized: "period.range.arrow.a11y") + " " + formatter.dayMonth(end)
        let spokenTotal = SummaryTexts(money: money, dates: formatter).spoken(total)
        return range + ", " + Self.spokenMeta(L10n.format("period.range.meta", dayCount, spokenTotal))
    }

    /// «· 15 дней ≈ …» → «15 дней ≈ …»: «·» VoiceOver не читают (INTEGRATION §5.3).
    private static func spokenMeta(_ meta: String) -> String {
        meta.replacingOccurrences(of: "·", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// При переполнении — без суммы (`risk` в copy.json).
    private var shortMeta: String {
        guard !draft.isAwaitingEnd, interval != nil else { return String(localized: "period.range.single") }
        return L10n.format("period.range.meta.short", dayCount)
    }

    // MARK: - Кнопка

    private var applyButton: some View {
        Button {
            guard let start = draft.start else { return }
            selection.applyCustom(from: start, through: draft.end ?? start)
            dismiss()
        } label: {
            Text(verbatim: L10n.format("period.apply", interval.map { formatter.range($0) } ?? ""))
        }
        .buttonStyle(.glassCapsule(.prominent))
        .disabled(interval == nil)
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.bottom, Theme.Spacing.sm)
    }

    // MARK: - Данные

    private var formatter: any DateTextFormatter { selection.dateFormatter }

    private var interval: DateInterval? { draft.interval(calendar: selection.calendar) }

    private var dayCount: Int {
        interval.map { PeriodSelection.dayCount(of: $0, calendar: selection.calendar) } ?? 0
    }

    private var earliestExpense: Date? { expenses.first?.date }

    /// Лента календаря: от самого раннего из «год назад», первой траты и начала выбора — до конца текущего месяца.
    private var firstMonth: Date {
        let calendar = selection.calendar
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: selection.today) ?? selection.today
        let earliest = [yearAgo, earliestExpense, draft.start].compactMap { $0 }.min() ?? yearAgo
        return calendar.dateInterval(of: .month, for: earliest)?.start ?? earliest
    }

    private func totalMinor(in interval: DateInterval) -> Int64 {
        let hidden = pendingDeletion.hiddenIDs
        let records = expenses.lazy
            .filter { !hidden.contains($0.id) }
            .map { ExpenseRecord($0) }
        let engine = StatisticsEngine(calendar: selection.calendar)
        return engine.summary(for: .custom(interval), records: Array(records), now: selection.now).totalMinor
    }
}

/// Высота шита (макет `10-period`): верх ниже строки шапки периода — за шитом видны месяц, ‹ › и ⚙.
/// Шит ниже `.large` в iOS 26 парит с полями, поэтому убавляется меньше высоты шапки: подобрано
/// на iPhone 17 (iOS 26.5) — верх шита ≈ 121 pt, на ≈ 6 pt ниже строки шапки.
private nonisolated struct PeriodSheetDetent: CustomPresentationDetent {
    static let headerClearance = Theme.Size.iconButton - Theme.Spacing.sm

    static func height(in context: Context) -> CGFloat? {
        context.maxDetentValue - headerClearance
    }
}
