import Foundation

/// Чтение выгрузки Monefy в CSV (в Monefy — «Настройки → Экспорт в файл»). Хранилище не трогает.
///
/// Формат — по файлу владельца и открытым парсерам Monefy на GitHub (buchhaltung, monefy2zenmoney, envelopes,
/// ai-budget-assistant, moniflow): UTF-8, часто с BOM; заголовок по-английски
/// `date,account,category,amount,currency,converted amount,currency,description` — два столбца `currency`
/// (валюта счёта и основная валюта Monefy). Разделитель столбцов — `,` или `;`. Дата — в формате устройства:
/// `3/21/2024`, `21/03/2024`, `21.03.2024`, `2024-03-21`. Сумма со знаком: минус — трата, плюс — доход;
/// разряды — пробел, неразрывный пробел или запятая (поле тогда в кавычках), дробная часть — точка или запятая.
/// Перевод между счетами — пара строк с категориями `To '<счёт>'` и `From '<счёт>'`, начальный остаток —
/// `Initial balance '<счёт>'`; эти подписи по-английски при любом языке Monefy.
public enum MonefyCSV {
    /// День траты без времени и часового пояса: в выгрузке Monefy времени нет.
    public struct Day: Hashable, Comparable, Sendable {
        public let year: Int
        public let month: Int
        public let day: Int

        public init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }

        /// День, на который приходится `date` в `calendar`.
        public init(_ date: Date, calendar: Calendar) {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
        }

        /// Начало дня в `calendar`.
        public func start(in calendar: Calendar) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }

        /// Полдень дня в `calendar` — дата импортированной траты: сдвиг часового пояса на несколько часов
        /// не переносит её на соседний день.
        public func noon(in calendar: Calendar) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        }

        public static func < (lhs: Day, rhs: Day) -> Bool {
            (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
        }

        var isValid: Bool {
            DateComponents(calendar: MonefyCSV.gregorian, year: year, month: month, day: day).isValidDate
        }
    }

    /// Трата из файла.
    public struct Expense: Equatable, Sendable {
        /// Строка файла, с которой начинается запись (заголовок — строка 1).
        public let line: Int
        public let day: Day
        /// Категория Monefy без пробелов по краям.
        public let category: String
        /// Сумма в сотых долях, > 0.
        public let amountMinor: Int64
        /// Описание из Monefy без пробелов по краям — заметка траты.
        public let note: String
        /// Код валюты суммы из файла (заглавными); пустой, если столбца нет.
        public let currencyCode: String
    }

    /// Прочитанный файл: траты и сколько строк пропущено, потому что это не траты.
    public struct File: Equatable, Sendable {
        /// Траты в порядке строк файла.
        public var expenses: [Expense] = []
        /// Доходы: сумма не меньше нуля.
        public var incomeCount = 0
        /// Переводы между счетами и начальные остатки счетов.
        public var transferCount = 0

        /// Коды валют трат по алфавиту.
        public var currencyCodes: [String] {
            Set(expenses.map(\.currencyCode).filter { !$0.isEmpty }).sorted()
        }
    }

    /// Читает выгрузку. Сумма берётся из `converted amount` — в основной валюте Monefy, одной на весь файл;
    /// без него — из `amount`.
    /// - Parameter dayFirstByDefault: порядок дня и месяца, если по датам файла его не понять
    ///   (во всех датах и день, и месяц ≤ 12). Monefy пишет дату в формате устройства, поэтому по умолчанию —
    ///   порядок формата текущей локали.
    public static func parse(
        _ data: Data,
        dayFirstByDefault: Bool = isDayFirst(in: .current)
    ) throws(MonefyCSVError) -> File {
        guard var text = String(data: data, encoding: .utf8) else { throw .notMonefyFile }
        if text.unicodeScalars.first == "\u{FEFF}" {
            text.unicodeScalars.removeFirst()
        }
        let records = records(in: text, delimiter: delimiter(of: text))
        guard let header = records.first, let columns = Columns(header: header.fields) else { throw .notMonefyFile }

        let rows = records.dropFirst().filter { record in
            // Пустые строки в конце файла Monefy иногда пишет одними разделителями.
            !record.fields.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        let dayFirst = isDayFirst(dates: rows.map { columns.value(columns.date, in: $0) }, default: dayFirstByDefault)
        let decimalSeparator = decimalSeparator(in: rows.flatMap { row in
            [columns.amount, columns.convertedAmount].compactMap { $0 }.map { columns.value($0, in: row) }
        })

        var file = File()
        for row in rows {
            guard row.fields.count > columns.requiredIndex else { throw .badRow(line: row.line, .missingField) }
            let category = columns.value(columns.category, in: row).trimmingCharacters(in: .whitespacesAndNewlines)
            if isTransfer(category) {
                file.transferCount += 1
                continue
            }
            let (amountIndex, currencyIndex) = columns.amountColumns(in: row)
            let amount: SignedMinor
            do {
                amount = try parseAmount(columns.value(amountIndex, in: row), decimalSeparator: decimalSeparator)
            } catch {
                throw .badRow(line: row.line, error)
            }
            guard amount.isNegative, amount.minor > 0 else {
                file.incomeCount += 1
                continue
            }
            guard amount.minor <= Money.maxAmountMinor else { throw .badRow(line: row.line, .amountTooLarge) }
            guard let day = parseDay(columns.value(columns.date, in: row), dayFirst: dayFirst) else {
                throw .badRow(line: row.line, .badDate)
            }
            file.expenses.append(Expense(
                line: row.line,
                day: day,
                category: category,
                amountMinor: amount.minor,
                note: columns.value(columns.description, in: row).trimmingCharacters(in: .whitespacesAndNewlines),
                currencyCode: columns.value(currencyIndex, in: row).trimmingCharacters(in: .whitespaces).uppercased()
            ))
        }
        guard !file.expenses.isEmpty else { throw .noExpenses }
        return file
    }

    /// Стоит ли день перед месяцем в коротком формате даты `locale` (`21.03.2024` — да, `3/21/2024` — нет).
    public static func isDayFirst(in locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "d/M/y"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return true }
        return day < month
    }

    static let gregorian = Calendar(identifier: .gregorian)
}

// MARK: - Записи CSV

extension MonefyCSV {
    struct Record: Equatable {
        /// Строка файла, с которой начинается запись.
        let line: Int
        let fields: [String]
    }

    /// Разделитель столбцов по первой строке: `;` или `,`.
    static func delimiter(of text: String) -> Unicode.Scalar {
        let header = text.unicodeScalars.prefix { $0 != "\n" && $0 != "\r" }
        let semicolons = header.count { $0 == ";" }
        let commas = header.count { $0 == "," }
        return semicolons > commas ? ";" : ","
    }

    /// Записи CSV (RFC 4180): поля в кавычках с `""` внутри и переводами строк, концы строк CR, LF и CRLF.
    /// Пустые строки пропускаются. Перебор по скалярам: в `String` пара CRLF — один `Character`.
    static func records(in text: String, delimiter: Unicode.Scalar) -> [Record] {
        let scalars = Array(text.unicodeScalars)
        var records: [Record] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var isQuoted = false
        var line = 1
        var recordLine = 1

        func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
        }
        func endRecord() {
            endField()
            if fields != [""] {
                records.append(Record(line: recordLine, fields: fields))
            }
            fields = []
        }

        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            if isQuoted {
                if scalar == "\"", next == "\"" {
                    field.append(scalar)
                    index += 1
                } else if scalar == "\"" {
                    isQuoted = false
                } else {
                    // Перевод строки внутри кавычек — часть поля; CRLF считается одной строкой.
                    if scalar == "\n" || (scalar == "\r" && next != "\n") { line += 1 }
                    field.append(scalar)
                }
            } else if scalar == "\"", field.isEmpty {
                isQuoted = true
            } else if scalar == delimiter {
                endField()
            } else if scalar == "\n" || scalar == "\r" {
                if scalar == "\r", next == "\n" { index += 1 }
                endRecord()
                line += 1
                recordLine = line
            } else {
                field.append(scalar)
            }
            index += 1
        }
        if !field.isEmpty || !fields.isEmpty {
            endRecord()
        }
        return records
    }

    /// Номера нужных столбцов.
    struct Columns {
        let date: Int
        let category: Int
        let amount: Int
        let currency: Int?
        let convertedAmount: Int?
        let convertedCurrency: Int?
        let description: Int?

        /// Заголовок по-английски — по именам. Иначе (переведённый заголовок) — по порядку столбцов Monefy,
        /// если он узнаётся по подписи формата: восемь столбцов и два одинаковых столбца валюты.
        init?(header: [String]) {
            let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if let date = names.firstIndex(of: "date"),
               let category = names.firstIndex(of: "category"),
               let amount = names.firstIndex(of: "amount") {
                let currencies = names.indices.filter { names[$0] == "currency" }
                self.date = date
                self.category = category
                self.amount = amount
                currency = currencies.first
                convertedAmount = names.firstIndex(of: "converted amount")
                convertedCurrency = currencies.dropFirst().first
                description = names.firstIndex(of: "description")
            } else if names.count == 8, !names[4].isEmpty, names[4] == names[6] {
                (date, category, amount) = (0, 2, 3)
                (currency, convertedAmount, convertedCurrency, description) = (4, 5, 6, 7)
            } else {
                return nil
            }
        }

        /// Без этих столбцов строка не читается.
        var requiredIndex: Int { max(date, category, amount) }

        /// Значение столбца; нет столбца или поля в строке — пусто.
        func value(_ index: Int?, in record: Record) -> String {
            guard let index, record.fields.indices.contains(index) else { return "" }
            return record.fields[index]
        }

        /// Сумма в основной валюте Monefy, если она есть в строке, иначе — в валюте счёта.
        func amountColumns(in record: Record) -> (amount: Int, currency: Int?) {
            if let convertedAmount, !value(convertedAmount, in: record).trimmingCharacters(in: .whitespaces).isEmpty {
                return (convertedAmount, convertedCurrency)
            }
            return (amount, currency)
        }
    }

    /// Перевод между счетами или начальный остаток: `To 'Карта'`, `From 'Наличные'`, `Initial balance 'Карта'`.
    /// Кавычки обязательны — обычная категория «To do» или «From grandma» переводом не считается.
    static func isTransfer(_ category: String) -> Bool {
        ["To '", "From '", "Initial balance '"].contains { prefix in
            category.hasPrefix(prefix) && category.hasSuffix("'") && category.count > prefix.count
        }
    }
}

// MARK: - Даты

extension MonefyCSV {
    /// Дата из файла до выбора порядка дня и месяца.
    private enum DateCell {
        /// `2024-03-21`.
        case yearFirst(year: Int, month: Int, day: Int)
        /// `21/03/2024`, `3/21/2024`, `21.03.2024`: порядок первых двух чисел — по всему файлу.
        case yearLast(first: Int, second: Int, year: Int)

        init?(_ raw: String) {
            let parts = raw.trimmingCharacters(in: .whitespaces)
                .split(omittingEmptySubsequences: false) { $0 == "/" || $0 == "." || $0 == "-" }
            guard
                parts.count == 3,
                parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
                let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2])
            else { return nil }
            switch (parts[0].count, parts[1].count, parts[2].count) {
            case (4, 1...2, 1...2): self = .yearFirst(year: a, month: b, day: c)
            case (1...2, 1...2, 4): self = .yearLast(first: a, second: b, year: c)
            default: return nil
            }
        }
    }

    /// Порядок дня и месяца в датах вида `a/b/yyyy`: число больше 12 бывает только днём.
    static func isDayFirst(dates: [String], default dayFirst: Bool) -> Bool {
        var firstOverTwelve = false
        var secondOverTwelve = false
        for case let .yearLast(first, second, _) in dates.compactMap(DateCell.init) {
            firstOverTwelve = firstOverTwelve || first > 12
            secondOverTwelve = secondOverTwelve || second > 12
        }
        if firstOverTwelve { return true }
        if secondOverTwelve { return false }
        return dayFirst
    }

    /// День из даты файла; `nil` — не дата или такого дня нет (`31.02.2024`, месяц 21 при выбранном порядке).
    static func parseDay(_ raw: String, dayFirst: Bool) -> Day? {
        let day: Day
        switch DateCell(raw) {
        case let .yearFirst(year, month, dayOfMonth):
            day = Day(year: year, month: month, day: dayOfMonth)
        case let .yearLast(first, second, year):
            day = dayFirst ? Day(year: year, month: second, day: first) : Day(year: year, month: first, day: second)
        case nil:
            return nil
        }
        return day.isValid ? day : nil
    }
}

// MARK: - Суммы

extension MonefyCSV {
    struct SignedMinor: Equatable {
        let isNegative: Bool
        /// Модуль суммы в сотых долях.
        let minor: Int64
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == "." || character == ","
    }

    /// Дробный разделитель файла (`.` или `,`) по суммам, где он однозначен: оба знака в числе (дробный — последний),
    /// знак повторяется (это разряды — дробный другой), после единственного знака не три цифры.
    /// `nil` — однозначных сумм нет: `1,250` тогда читается как разряды.
    static func decimalSeparator(in amounts: [String]) -> Character? {
        var dots = 0
        var commas = 0
        for raw in amounts {
            let text = raw.filter { isSeparator($0) || $0.isNumber }
            guard let last = text.lastIndex(where: isSeparator) else { continue }
            let separator = text[last]
            let before = text[..<last].filter(isSeparator)
            let vote: Character?
            if before.contains(where: { $0 != separator }) {
                vote = separator
            } else if !before.isEmpty {
                vote = separator == "." ? "," : "."
            } else {
                vote = text[text.index(after: last)...].count == 3 ? nil : separator
            }
            switch vote {
            case ".": dots += 1
            case ",": commas += 1
            default: break
            }
        }
        if dots == 0, commas == 0 { return nil }
        return dots >= commas ? "." : ","
    }

    /// Сумма со знаком: `-10`, `-25.50`, `-25,50`, `-1 250`, `-1,250.00`, `-1.250,00`, `+5000`. Больше двух знаков
    /// после запятой (пересчёт в основную валюту) округляются до сотых, половина — от нуля.
    static func parseAmount(_ raw: String, decimalSeparator: Character?) throws(MonefyCSVError.RowProblem) -> SignedMinor {
        var text = raw.filter { !$0.isWhitespace }
        var isNegative = false
        if let sign = text.first, sign == "-" || sign == "\u{2212}" || sign == "+" {
            isNegative = sign != "+"
            text.removeFirst()
        }
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isNumber || isSeparator($0)) }) else {
            throw .badAmount
        }

        var integer = Substring(text)
        var fraction = Substring("")
        if let last = text.lastIndex(where: isSeparator) {
            let separator = text[last]
            let before = text[..<last]
            let isDecimal = if before.contains(where: { isSeparator($0) && $0 != separator }) {
                true
            } else if before.contains(separator) {
                false
            } else if let decimalSeparator {
                separator == decimalSeparator
            } else {
                text[text.index(after: last)...].count != 3
            }
            if isDecimal {
                integer = before
                fraction = text[text.index(after: last)...]
                guard !fraction.isEmpty else { throw .badAmount }
            }
        }
        guard let units = integerUnits(integer) else { throw .badAmount }

        let cents = Int64(fraction.prefix(2).padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        let roundsUp = fraction.dropFirst(2).first.map { $0 >= "5" } ?? false
        let (scaled, multiplyOverflow) = units.multipliedReportingOverflow(by: Money.minorUnitsPerMajor)
        let (minor, addOverflow) = scaled.addingReportingOverflow(cents + (roundsUp ? 1 : 0))
        guard !multiplyOverflow, !addOverflow else { throw .amountTooLarge }
        return SignedMinor(isNegative: isNegative, minor: minor)
    }

    /// Целая часть с разрядами одним знаком: `1250`, `1,250`, `1.250.000`. Группы после первой — по три цифры.
    /// `nil` — не число; пустая часть (`.50`) — ноль. Переполнение — `Int64.max` (дальше — «слишком большая сумма»).
    private static func integerUnits(_ text: Substring) -> Int64? {
        let groups = text.split(omittingEmptySubsequences: false, whereSeparator: isSeparator)
        let separators = Set(text.filter(isSeparator))
        guard separators.count <= 1 else { return nil }
        if groups.count > 1 {
            guard
                let head = groups.first, (1...3).contains(head.count),
                groups.dropFirst().allSatisfy({ $0.count == 3 })
            else { return nil }
        }
        let digits = groups.joined()
        if digits.isEmpty { return 0 }
        return Int64(digits) ?? Int64.max
    }
}

// MARK: - Ошибки

/// Почему выгрузку Monefy нельзя прочитать. Тексты — `design/copy.json` (`error.monefy.*`):
/// для строки — `error.monefy.row.<RowProblem.rawValue>` с номером строки.
public enum MonefyCSVError: Error, Equatable, Sendable {
    /// Что не так в строке файла.
    public enum RowProblem: String, Error, Equatable, Sendable {
        /// Столбцов меньше, чем в заголовке до даты, категории и суммы.
        case missingField
        /// Дата не читается или такого дня нет.
        case badDate
        /// Сумма не число.
        case badAmount
        /// Сумма больше `Money.maxAmountMinor`.
        case amountTooLarge
    }

    /// Не текст UTF-8 или нет заголовка Monefy.
    case notMonefyFile
    /// Файл прочитан, но трат в нём нет: только доходы и переводы.
    case noExpenses
    /// Ошибка в строке `line` файла (заголовок — строка 1).
    case badRow(line: Int, RowProblem)
}
