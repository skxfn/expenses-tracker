/// Свои таблицы словоформ: системных форм в нужных падежах нет, а сокращения месяцев D7 — без точки.
/// Предлоги сюда не входят — фразу собирает App по design/copy.json («в %@», «по %@»).
public enum RussianWords {
    public enum MonthForm: Sendable {
        /// «сентябрь» — он же винительный: «за сентябрь», «итог за сентябрь».
        case nominative
        /// «октября» — в датах: «8 октября», «к 31 октября».
        case genitive
        /// «августе» — «в августе».
        case prepositional
        /// «окт», «мая» — в коротких датах D7, без точки.
        case abbreviated
    }

    public enum WeekdayForm: Sendable {
        /// «пятница»
        case nominative
        /// «воскресенью» — «к воскресенью».
        case dativeSingular
        /// «пятницам» — «по пятницам».
        case dativePlural
        /// «чт» — «чт, 8 окт».
        case abbreviated
    }

    /// - Parameter month: 1…12.
    public static func month(_ month: Int, _ form: MonthForm) -> String {
        precondition((1...12).contains(month), "Месяц вне 1…12: \(month)")
        let table = switch form {
        case .nominative: monthsNominative
        case .genitive: monthsGenitive
        case .prepositional: monthsPrepositional
        case .abbreviated: monthsAbbreviated
        }
        return table[month - 1]
    }

    /// - Parameter weekday: нумерация `Calendar`: 1 — воскресенье … 7 — суббота.
    public static func weekday(_ weekday: Int, _ form: WeekdayForm) -> String {
        precondition((1...7).contains(weekday), "День недели вне 1…7: \(weekday)")
        let table = switch form {
        case .nominative: weekdaysNominative
        case .dativeSingular: weekdaysDativeSingular
        case .dativePlural: weekdaysDativePlural
        case .abbreviated: weekdaysAbbreviated
        }
        return table[weekday - 1]
    }

    /// Первая буква заглавная: «Октябрь», «Чт, 8 окт».
    public static func capitalized(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst()
    }

    private static let monthsNominative = [
        "январь", "февраль", "март", "апрель", "май", "июнь",
        "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"
    ]
    private static let monthsGenitive = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря"
    ]
    private static let monthsPrepositional = [
        "январе", "феврале", "марте", "апреле", "мае", "июне",
        "июле", "августе", "сентябре", "октябре", "ноябре", "декабре"
    ]
    /// Три буквы как `stats.year.months` в copy.json; для мая в датах — «мая» (своей формы в copy.json нет).
    private static let monthsAbbreviated = [
        "янв", "фев", "мар", "апр", "мая", "июн",
        "июл", "авг", "сен", "окт", "ноя", "дек"
    ]
    private static let weekdaysNominative = [
        "воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"
    ]
    private static let weekdaysDativeSingular = [
        "воскресенью", "понедельнику", "вторнику", "среде", "четвергу", "пятнице", "субботе"
    ]
    private static let weekdaysDativePlural = [
        "воскресеньям", "понедельникам", "вторникам", "средам", "четвергам", "пятницам", "субботам"
    ]
    private static let weekdaysAbbreviated = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
}
