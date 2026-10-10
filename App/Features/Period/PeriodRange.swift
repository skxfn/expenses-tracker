import Foundation
import SwiftUI
import ExpenseCore

/// Диапазон, который набирают в шите «Период»: дни включительно, начала дней.
/// Первое касание задаёт начало, второе — конец (раньше начала — меняются местами), третье начинает заново.
struct PeriodRangeDraft: Equatable {
    private(set) var start: Date?
    private(set) var end: Date?

    /// Начальный диапазон — просматриваемый период, обрезанный по сегодня (будущие дни не выбираются).
    init(period: StatsPeriod, today: Date, calendar: Calendar) {
        let first = min(calendar.startOfDay(for: period.interval.start), today)
        let lastMoment = max(period.interval.start, period.interval.end.addingTimeInterval(-1))
        start = first
        end = max(first, min(calendar.startOfDay(for: lastMoment), today))
    }

    /// Выбран только первый день: ждём конец (`period.range.single`).
    var isAwaitingEnd: Bool { start != nil && end == nil }

    mutating func tap(_ day: Date) {
        guard let start, end == nil else {
            start = day
            end = nil
            return
        }
        if day < start {
            self.start = day
            end = start
        } else {
            end = day
        }
    }

    /// Полуоткрытый интервал выбора; с одним днём — этот день.
    func interval(calendar: Calendar) -> DateInterval? {
        guard let start else { return nil }
        return PeriodSelection.dayInterval(from: start, through: end ?? start, calendar: calendar)
    }

    func contains(_ day: Date) -> Bool {
        guard let start else { return false }
        return start <= day && day <= (end ?? start)
    }
}

/// Готовые периоды шита (§8 п. 2: без «Эта неделя / Этот месяц / Этот год» — они дублируют сегмент).
enum PeriodPreset: CaseIterable, Identifiable {
    case lastMonth, last30Days, last3Months, allTime

    var id: Self { self }

    var titleKey: LocalizedStringKey {
        switch self {
        case .lastMonth: "period.preset.lastMonth"
        case .last30Days: "period.preset.last30Days"
        case .last3Months: "period.preset.last3Months"
        case .allTime: "period.preset.allTime"
        }
    }

    /// «Прошлый месяц» — календарный месяц (сегмент «Месяц»); остальные — свой период, кончающийся сегодня.
    /// `nil` — периода нет («Всё время» без трат).
    func period(today: Date, earliestExpense: Date?, calendar: Calendar) -> StatsPeriod? {
        let first: Date?
        switch self {
        case .lastMonth:
            return StatsPeriod.current(.month, now: today, calendar: calendar).previous(in: calendar)
        case .last30Days:
            first = calendar.date(byAdding: .day, value: -29, to: today)
        case .last3Months:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            first = calendar.date(byAdding: .month, value: -3, to: tomorrow)
        case .allTime:
            first = earliestExpense.map { min(calendar.startOfDay(for: $0), today) }
        }
        return first.map { .custom(PeriodSelection.dayInterval(from: $0, through: today, calendar: calendar)) }
    }
}
