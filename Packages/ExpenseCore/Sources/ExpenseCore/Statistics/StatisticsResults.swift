import Foundation

/// Сводка за период. Суммы — в сотых долях валюты.
public struct StatsSummary: Sendable, Hashable {
    public let totalMinor: Int64
    public let count: Int
    /// Средняя трата в день, округлённая до сотой доли (половина — от нуля).
    public let averagePerDayMinor: Int64
    /// Число дней, по которым считалась средняя: для текущего периода — прошедшие дни
    /// включая сегодняшний, для остальных — все дни периода.
    public let averagedDayCount: Int
    public let previousTotalMinor: Int64
    /// Относительное изменение к предыдущему периоду: `0.25` — рост на 25 %.
    /// `nil`, если в предыдущем периоде трат не было.
    public let change: Double?
}

/// Строка разбивки по категориям.
public struct StatsCategoryShare: Sendable, Hashable, Identifiable {
    /// `nil` — расходы без категории.
    public let categoryID: UUID?
    public let totalMinor: Int64
    public let count: Int
    /// Доля в итоге периода, 0…1.
    public let share: Double

    public var id: UUID? { categoryID }
}

/// Шаг временного ряда.
public enum StatsTimeStep: Sendable, Hashable, CaseIterable {
    case hour
    case day
    case week
    case month

    /// Единица для оси Swift Charts (`.value(_:_:unit:)`).
    public var calendarComponent: Calendar.Component {
        switch self {
        case .hour: .hour
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

/// Отрезок временного ряда. Интервал обрезан границами периода.
public struct StatsTimeBucket: Sendable, Hashable, Identifiable {
    public let interval: DateInterval
    public let totalMinor: Int64
    public let count: Int

    public var id: Date { interval.start }
}

/// Временной ряд за период: все отрезки подряд, пустые — с нулями.
public struct StatsTimeSeries: Sendable, Hashable {
    public let step: StatsTimeStep
    public let buckets: [StatsTimeBucket]
}

/// Точка накопительной кривой.
public struct StatsCumulativePoint: Sendable, Hashable, Identifiable {
    /// Номер дня в периоде, начиная с 1 — общая ось для сравнения периодов.
    public let dayNumber: Int
    /// Начало дня.
    public let date: Date
    /// Сумма трат с начала периода по этот день включительно.
    public let cumulativeMinor: Int64

    public var id: Int { dayNumber }
}

/// Накопительные кривые текущего и предыдущего периода, выровненные по номеру дня.
public struct StatsCumulativeComparison: Sendable, Hashable {
    /// Для текущего периода — только по сегодняшний день включительно.
    public let current: [StatsCumulativePoint]
    /// Все дни предыдущего периода.
    public let previous: [StatsCumulativePoint]
}

/// Средние траты в один из дней недели.
public struct StatsWeekdayAverage: Sendable, Hashable, Identifiable {
    /// День недели в нумерации `Calendar`: 1 — воскресенье … 7 — суббота.
    public let weekday: Int
    /// Сколько таких дней недели вошло в расчёт.
    public let dayCount: Int
    public let totalMinor: Int64
    /// `totalMinor / dayCount` с округлением; 0, если таких дней не было.
    public let averageMinor: Int64

    public var id: Int { weekday }
}
