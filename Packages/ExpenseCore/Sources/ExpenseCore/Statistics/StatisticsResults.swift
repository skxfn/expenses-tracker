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
    /// Итог отрезка прошлого периода `comparisonInterval` («к той же дате»).
    public let previousTotalMinor: Int64
    /// Относительное изменение к `previousTotalMinor`: `0.25` — рост на 25 %.
    /// `nil`, если в сравниваемом отрезке трат не было.
    public let change: Double?
    /// С каким отрезком прошлого периода сравнивается итог — `StatisticsEngine.comparisonInterval(for:now:)`.
    public let comparisonInterval: DateInterval
    /// С чем сравнили — для фразы-сравнения.
    public let comparisonReference: StatsComparisonReference

    /// Разница со знаком: `totalMinor − previousTotalMinor`. Во фразе — модуль («на 38 Br меньше»).
    public var differenceMinor: Int64 { totalMinor - previousTotalMinor }

    /// Какую фразу-сравнение показать. «примерно как» — |изменение| < `StatsThresholds.sameChange`.
    public var trend: StatsTrend {
        guard let change else { return .noPrevious }
        if abs(change) < StatsThresholds.sameChange { return .same }
        return change > 0 ? .more : .less
    }
}

/// Направление сравнения с прошлым периодом (`home.compare*` в design/copy.json).
public enum StatsTrend: Sendable, Hashable {
    /// «на 38 Br больше, чем …»
    case more
    /// «на 38 Br меньше, чем …»
    case less
    /// «примерно как …»
    case same
    /// «… трат не было»
    case noPrevious
}

/// С чем сравнивается итог (D5). Текст — `RussianDateFormatter.comparisonReference(_:)`.
public enum StatsComparisonReference: Sendable, Hashable {
    /// Идущий день — «вчера».
    case yesterday
    /// Прошедший день — «накануне».
    case dayBefore
    /// Идущая неделя — «на прошлой неделе».
    case lastWeek
    /// Идущий месяц — «в прошлом месяце».
    case lastMonth
    /// Идущий год — «в прошлом году».
    case lastYear
    /// Прошедший месяц — с предыдущим по имени: «в августе». Номер месяца 1…12.
    case month(Int)
    /// Прошедший год — «в 2024».
    case year(Int)
    /// Прошедшая неделя и свой период — датами предыдущего отрезка: «за 22–28 сен», «за 2–4 окт».
    case range(DateInterval)
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

/// Категория верхнего уровня в разбивке периода вместе с подкатегориями.
public struct StatsGroupShare: Sendable, Hashable, Identifiable {
    /// `nil` — «Без категории».
    public let groupID: UUID?
    /// Траты категории и всех её подкатегорий.
    public let totalMinor: Int64
    public let count: Int
    /// Доля в итоге периода, 0…1.
    public let share: Double
    /// Подкатегории с тратами в периоде; `share` — доля в итоге категории («69% категории»).
    /// Порядок — по ступеням (`stepRank`), подкатегории без ранга — после, по сумме.
    public let subcategories: [StatsCategoryShare]
    /// Траты, записанные прямо в категорию («без подкатегории»). Есть ли у категории подкатегории,
    /// движок не знает: подпись «подкатегорий нет» UI ставит по каталогу.
    /// У строки «Без категории» — весь её итог.
    public let unassignedMinor: Int64
    public let unassignedCount: Int

    /// Доля «без подкатегории» в итоге категории, 0…1.
    public var unassignedShare: Double {
        totalMinor == 0 ? 0 : Double(unassignedMinor) / Double(totalMinor)
    }

    public var id: UUID? { groupID }
}

/// Категории после сворачивания мелких в «Ещё N».
public struct StatsFoldedGroups: Sendable, Hashable {
    /// Показываются по отдельности; порядок — как на входе.
    public let visible: [StatsGroupShare]
    /// Свёрнуты в «Ещё N»; порядок — как на входе. Пусто — сворачивать нечего.
    public let folded: [StatsGroupShare]

    public var foldedTotalMinor: Int64 { folded.reduce(0) { $0 + $1.totalMinor } }
    public var foldedShare: Double { folded.reduce(0) { $0 + $1.share } }
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

    /// Отрезок с наибольшей суммой («больше всего 2 окт»); при равенстве — более ранний. `nil` — трат нет.
    public var peak: StatsTimeBucket? {
        let peak = buckets.max { $1.totalMinor > $0.totalMinor }
        return peak.flatMap { $0.totalMinor > 0 ? $0 : nil }
    }
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

/// Прогноз итога идущего периода при текущем темпе.
public struct StatsForecast: Sendable, Hashable {
    /// Точный прогноз в сотых долях валюты.
    public let projectedMinor: Int64
    /// Прошло дней периода, включая сегодня.
    public let elapsedDayCount: Int
    /// Дней в периоде.
    public let dayCount: Int

    /// Для показа «≈ 1 600 Br»: `StatsThresholds.forecastSignificantDigits` значащих цифр в целых единицах.
    public var roundedMinor: Int64 {
        Money.roundedToSignificantDigits(projectedMinor, digits: StatsThresholds.forecastSignificantDigits)
    }
}

/// «Привычки»: средние по дням недели и выводы словами.
public struct StatsHabits: Sendable, Hashable {
    /// Всегда 7 элементов, первый — `calendar.firstWeekday`.
    public let averages: [StatsWeekdayAverage]
    /// День недели с наибольшей средней («по пятницам»), нумерация `Calendar`: 1 — воскресенье.
    /// При равенстве — первый по порядку недели. `nil` — трат нет.
    public let peakWeekday: Int?
    /// Будни против выходных. `nil` — в периоде (по сегодня) ещё нет будней или выходных.
    public let split: StatsWeekSplit?
}

/// Где средняя за день больше: в будни (пн–пт) или в выходные (сб–вс).
public enum StatsWeekSplit: Sendable, Hashable {
    /// «В будни тратится больше, чем в выходные»
    case weekdays
    /// «В выходные тратится больше, чем в будни»
    case weekend
    /// «В будни и в выходные — почти поровну»: разница меньше `StatsThresholds.weekSplitTie`.
    case even
}

/// Шкала заливки календаря и тепловой карты: heat-0…heat-4, одна на год.
public struct StatsHeatScale: Sendable, Hashable {
    /// Нижние границы ступеней 2, 3 и 4 в сотых долях валюты, по возрастанию, кратны целой единице:
    /// `[2_500, 5_000, 7_500]` — легенда «0 · до 25 · 25+ · 50+ · 75+».
    public let thresholds: [Int64]

    /// Ступень дня: 0 — трат нет, 1 — меньше первой границы, …, 4 — от последней границы.
    public func level(forMinor amount: Int64) -> Int {
        guard amount > 0 else { return 0 }
        return 1 + thresholds.count { amount >= $0 }
    }
}
