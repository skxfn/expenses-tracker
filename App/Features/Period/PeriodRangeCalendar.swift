import SwiftUI
import ExpenseCore

/// Календарь шита «Период» на бумажном листе (макет `10-period`): сплошная лента недель от первого месяца
/// до конца текущего, над первым числом месяца — «окт». Концы диапазона — графитовые круги 48 с текстом onInk,
/// середина — полоса графит 10 % от края до края листа. Будущие дни неактивны.
/// Сверху — месяц и год верхней видимой недели и дни недели (`cal.weekdays.*`).
struct PeriodRangeCalendar: View {
    let calendar: Calendar
    /// Начало сегодняшнего дня.
    let today: Date
    /// С какого месяца начинать ленту.
    let firstMonth: Date
    @Binding var draft: PeriodRangeDraft

    /// Недели ленты (начала недель) и начальная верхняя неделя — считаются один раз при открытии.
    private let weeks: [Date]
    private let initialWeek: Date
    /// Последний показанный день — конец текущего месяца.
    private let lastDay: Date
    @State private var position: ScrollPosition
    /// Номер верхней видимой недели — по смещению прокрутки (`nil` до первого замера).
    @State private var topWeekIndex: Int?
    /// Начальная позиция больше не поправляется (`settleInitialPosition`): поправлена или ленту уже листали.
    @State private var isPositionSettled = false

    /// Полоса между концами: графит 10 % (DESIGN.md → Period Picker).
    static let bandOpacity: Double = 0.1
    static let rowHeight: CGFloat = 48

    init(calendar: Calendar, today: Date, firstMonth: Date, draft: Binding<PeriodRangeDraft>) {
        self.calendar = calendar
        self.today = today
        self.firstMonth = firstMonth
        _draft = draft
        let lastDay = Self.lastDay(today: today, calendar: calendar)
        let weeks = Self.weeks(from: firstMonth, through: lastDay, calendar: calendar)
        let initialWeek = Self.initialWeek(anchor: draft.wrappedValue.start ?? today, weeks: weeks, calendar: calendar)
        self.weeks = weeks
        self.initialWeek = initialWeek
        self.lastDay = lastDay
        // Начальная позиция — сразу в `ScrollPosition`: `scrollTo` в `onAppear` у `LazyVStack` промахивается.
        _position = State(initialValue: ScrollPosition(id: initialWeek, anchor: .top))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(verbatim: monthTitle(for: visibleWeek))
                    .typeStyle(.headline)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .accessibilityAddTraits(.isHeader)
                weekdayHeader
                    .padding(.horizontal, Theme.Spacing.screen)
            }
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.sm)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(weeks, id: \.self) { week in
                        PeriodWeekRow(calendar: calendar, weekStart: week, today: today, firstDay: firstMonth,
                                      lastDay: lastDay, draft: $draft)
                    }
                }
                .scrollTargetLayout()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("period.days.a11y")
            }
            .scrollPosition($position, anchor: .top)
            .onScrollGeometryChange(for: CalendarScroll.self) { geometry in
                CalendarScroll(geometry, rowHeight: Self.rowHeight)
            } action: { _, scroll in
                topWeekIndex = scroll.topIndex
                settleInitialPosition(scroll)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting { isPositionSettled = true }
            }
        }
        // Сетка 7 × 48 жёсткая (INTEGRATION §6): крупнее — Large Content Viewer у дней, как в календаре.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .paperSheetBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("period.calendar.a11y")
    }

    // MARK: - Шапка календаря

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdayOrder, id: \.self) { weekday in
                Text(Self.weekdayKey(weekday))
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// Нумерация `Calendar` (1 — воскресенье) в порядке недели с `calendar.firstWeekday`.
    private var weekdayOrder: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private static func weekdayKey(_ weekday: Int) -> LocalizedStringKey {
        switch weekday {
        case 1: "cal.weekdays.sun"
        case 2: "cal.weekdays.mon"
        case 3: "cal.weekdays.tue"
        case 4: "cal.weekdays.wed"
        case 5: "cal.weekdays.thu"
        case 6: "cal.weekdays.fri"
        default: "cal.weekdays.sat"
        }
    }

    /// «Сентябрь 2026»: месяц середины недели (у недели на стыке месяцев — того, где больше её дней).
    private func monthTitle(for week: Date) -> String {
        let middle = calendar.date(byAdding: .day, value: 3, to: week) ?? week
        let month = dates.monthTitle(calendar.component(.month, from: middle))
        return month + TextSpacing.nonBreaking + String(calendar.component(.year, from: middle))
    }

    /// Даты и названия месяцев на языке интерфейса.
    private var dates: any DateTextFormatter {
        AppLanguage.current.dateFormatter(calendar: calendar, now: today)
    }

    // MARK: - Недели

    /// Неделя под шапкой — по смещению прокрутки (строки одной высоты), а не `position.viewID`: у конца ленты
    /// (выбор в текущем месяце) прокрутка упирается в край и показывает недели раньше запрошенной,
    /// а `viewID` остаётся запрошенным — заголовок «Сентябрь» над августовскими строками.
    private var visibleWeek: Date {
        guard let topWeekIndex, !weeks.isEmpty else { return initialWeek }
        return weeks[min(max(topWeekIndex, 0), weeks.count - 1)]
    }

    /// Неделя выбора у конца ленты (выбор в текущем месяце) наверх встать не может: прокрутка упирается
    /// в край без учёта кнопки «Показать», и последние недели — с концом выбора — оказываются под ней.
    /// Тогда лента прокручивается до конца по-честному: последняя неделя над кнопкой.
    /// Проверяется на каждом замере, пока ленту не листали: первые замеры при появлении шита бывают промежуточными.
    private func settleInitialPosition(_ scroll: CalendarScroll) {
        guard !isPositionSettled, scroll.visibleHeight > 0 else { return }
        let initialIndex = weeks.firstIndex(of: initialWeek) ?? 0
        let maxTopOffset = CGFloat(weeks.count) * Self.rowHeight - scroll.visibleHeight
        if CGFloat(initialIndex) * Self.rowHeight > maxTopOffset {
            isPositionSettled = true
            position.scrollTo(edge: .bottom)
        }
    }

    private static func lastDay(today: Date, calendar: Calendar) -> Date {
        let month = calendar.dateInterval(of: .month, for: today)
        return month.flatMap { calendar.date(byAdding: .day, value: -1, to: $0.end) } ?? today
    }

    private static func weeks(from firstMonth: Date, through lastDay: Date, calendar: Calendar) -> [Date] {
        guard let first = calendar.dateInterval(of: .weekOfYear, for: firstMonth)?.start else { return [] }
        var result: [Date] = []
        var week = first
        while week <= lastDay {
            result.append(week)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
            week = next
        }
        return result
    }

    /// Неделя начала выбора — третьей строкой, как в макете.
    private static func initialWeek(anchor: Date, weeks: [Date], calendar: Calendar) -> Date {
        let week = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? anchor
        let shifted = calendar.date(byAdding: .weekOfYear, value: -2, to: week) ?? week
        return max(shifted, weeks.first ?? shifted)
    }
}

/// Замер прокрутки ленты: верхняя видимая неделя и высота видимой части (без шапки и кнопки).
private struct CalendarScroll: Equatable {
    let topIndex: Int
    let visibleHeight: CGFloat

    init(_ geometry: ScrollGeometry, rowHeight: CGFloat) {
        topIndex = Int(((geometry.contentOffset.y + geometry.contentInsets.top) / rowHeight).rounded())
        visibleHeight = geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
    }
}

/// Неделя ленты: 7 дней и полоса диапазона под ними.
private struct PeriodWeekRow: View {
    let calendar: Calendar
    let weekStart: Date
    let today: Date
    let firstDay: Date
    let lastDay: Date
    @Binding var draft: PeriodRangeDraft

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                PeriodDayCell(
                    calendar: calendar,
                    day: day,
                    today: today,
                    isShown: day >= calendar.startOfDay(for: firstDay) && day <= lastDay,
                    draft: $draft
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .frame(height: PeriodRangeCalendar.rowHeight)
        .background { band }
    }

    /// Полоса графит 10 %: от центра конца до центра конца, через перенос недели — до края листа.
    @ViewBuilder
    private var band: some View {
        if let start = draft.start, let end = draft.end, start != end,
           let first = days.first, let last = days.last, start <= last, end >= first {
            GeometryReader { proxy in
                let column = (proxy.size.width - 2 * Theme.Spacing.screen) / 7
                let center = { (day: Date) -> CGFloat in
                    let index = calendar.dateComponents([.day], from: first, to: day).day ?? 0
                    return Theme.Spacing.screen + column * (CGFloat(index) + 0.5)
                }
                let left = start < first ? 0 : center(start)
                let right = end > last ? proxy.size.width : center(end)
                Rectangle()
                    .fill(Theme.ink.opacity(PeriodRangeCalendar.bandOpacity))
                    .frame(width: max(right - left, 0))
                    .offset(x: left)
            }
            .accessibilityHidden(true)
        }
    }
}

/// День: число SF 17; концы диапазона — графитовый круг 48; будущие — серым и неактивны.
private struct PeriodDayCell: View {
    let calendar: Calendar
    let day: Date
    let today: Date
    let isShown: Bool
    @Binding var draft: PeriodRangeDraft

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isFuture: Bool { day > today }
    private var isEndpoint: Bool { day == draft.start || day == draft.end }
    private var isFirstOfMonth: Bool { calendar.component(.day, from: day) == 1 }
    private var dates: any DateTextFormatter { AppLanguage.current.dateFormatter(calendar: calendar, now: today) }

    var body: some View {
        if isShown {
            Button {
                draft.tap(day)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .disabled(isFuture)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(draft.contains(day) ? .isSelected : [])
            .accessibilityShowsLargeContentViewer {
                Text(verbatim: isFirstOfMonth ? dates.short(day) : number)
            }
        } else {
            Color.clear
                .frame(height: PeriodRangeCalendar.rowHeight)
                .accessibilityHidden(true)
        }
    }

    /// Отступ метки месяца от верха круга на крупном тексте (число 28 занимает середину круга 48).
    private static let compactLabelInset: CGFloat = 1

    private var number: String { "\(calendar.component(.day, from: day))" }
    /// «окт» над 1-м числом.
    private var monthLabel: String { dates.monthShort(calendar.component(.month, from: day)) }

    private var label: some View {
        Text(verbatim: number)
            .typeStyle(.body)
            .monospacedDigit()
            .foregroundStyle(numberColor)
            .frame(width: PeriodRangeCalendar.rowHeight, height: PeriodRangeCalendar.rowHeight)
            .background {
                if isEndpoint {
                    Circle()
                        .fill(Theme.ink)
                        .paperShadow(Tokens.Shadow.segmentActive)
                }
            }
            .overlay(alignment: .top) {
                // Метка месяца над 1-м числом — и на конце диапазона: иначе «1–10 окт» выглядит сентябрём.
                // В круге 48 метке и числу тесно: метка не растёт с размером текста (месяц есть в VoiceOver
                // и Large Content Viewer), а на крупном тексте поднимается к краю, чтобы не задеть число.
                if isFirstOfMonth {
                    Text(verbatim: monthLabel)
                        .typeStyle(.caption)
                        .foregroundStyle(isEndpoint ? Theme.onInk : Theme.secondary)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .padding(.top, dynamicTypeSize.isAccessibilitySize ? Self.compactLabelInset : Theme.Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
    }

    private var numberColor: Color {
        if isEndpoint { return Theme.onInk }
        return isFuture ? Theme.tertiary : Theme.ink
    }

    private var accessibilityLabel: String {
        let date = dates.dayMonth(day)
        if day == draft.start, draft.end != nil, draft.end != day {
            return L10n.format("period.start.a11y", date)
        }
        if day == draft.end {
            return L10n.format(day == today ? "period.end.a11y.today" : "period.end.a11y", date)
        }
        return date
    }
}
