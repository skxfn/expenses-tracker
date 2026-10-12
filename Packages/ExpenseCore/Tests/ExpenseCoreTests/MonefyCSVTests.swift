import Foundation
import Testing
@testable import ExpenseCore

/// Синтетические выгрузки Monefy (данные выдуманы) в форматах, найденных в файле владельца и в открытых парсерах.
enum MonefyFixture {
    static let header = "date,account,category,amount,currency,converted amount,currency,description"

    /// Строки через CRLF, как пишет Monefy; `bom` — UTF-8 BOM в начале.
    static func data(_ lines: [String], bom: Bool = true, newline: String = "\r\n") -> Data {
        Data(((bom ? "\u{FEFF}" : "") + lines.joined(separator: newline) + newline).utf8)
    }

    static func parse(_ lines: [String], dayFirst: Bool = true) throws -> MonefyCSV.File {
        try MonefyCSV.parse(data(lines), dayFirstByDefault: dayFirst)
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> MonefyCSV.Day {
        MonefyCSV.Day(year: year, month: month, day: day)
    }
}

@Suite struct MonefyCSVTests {
    private typealias F = MonefyFixture

    // MARK: - Формат файла владельца

    @Test func readsOwnerFormatWithBOMTwoCurrencyColumnsAndMonthFirstDates() throws {
        let file = try F.parse([
            F.header,
            "3/21/2024,Cash,Taxi,-10,GBP,-10,GBP,",
            "3/21/2024,Cash,Food,-4.5,GBP,-4.5,GBP,Хлеб",
            "10/7/2026,Card,Eating out,-1234.56,GBP,-1234.56,GBP,  Кофе  ",
        ], dayFirst: true)

        #expect(file.expenses.map(\.day) == [F.day(2024, 3, 21), F.day(2024, 3, 21), F.day(2026, 10, 7)])
        #expect(file.expenses.map(\.category) == ["Taxi", "Food", "Eating out"])
        #expect(file.expenses.map(\.amountMinor) == [1000, 450, 123_456])
        #expect(file.expenses.map(\.note) == ["", "Хлеб", "Кофе"])
        #expect(file.expenses.map(\.line) == [2, 3, 4])
        #expect(file.currencyCodes == ["GBP"])
        #expect(file.incomeCount == 0 && file.transferCount == 0)
    }

    @Test func readsWithoutBOMAndWithLFLineEnds() throws {
        let data = F.data([F.header, "21/03/2024,Cash,Food,-10,BYN,-10,BYN,"], bom: false, newline: "\n")
        let file = try MonefyCSV.parse(data, dayFirstByDefault: false)
        #expect(file.expenses.map(\.day) == [F.day(2024, 3, 21)])
    }

    // MARK: - Варианты выгрузки

    @Test func readsSemicolonFileWithCommaDecimalsAndSpaceThousands() throws {
        let file = try F.parse([
            "date;account;category;amount;currency;converted amount;currency;description",
            "21/03/2024;Наличные;Еда;-1\u{00A0}250,50;BYN;-1\u{00A0}250,50;BYN;Продукты",
            "22/03/2024;Наличные;Связь;-12\u{202F}000;BYN;-12\u{202F}000;BYN;",
            "23/03/2024;Карта;Кафе;-4,6;BYN;-4,6;BYN;",
        ])

        #expect(file.expenses.map(\.amountMinor) == [125_050, 1_200_000, 460])
        #expect(file.expenses.map(\.category) == ["Еда", "Связь", "Кафе"])
    }

    @Test func readsSemicolonFileWithDotDecimalsAndNonBreakingThousands() throws {
        // Русская выгрузка (monefy2zenmoney, envelopes): `;`, разряды — неразрывный пробел, дробная часть — точка.
        let file = try F.parse([
            "date;account;category;amount;currency;converted amount;currency;description",
            "01/02/2024;Наличные;Еда;-2\u{00A0}500;RUB;-2\u{00A0}500;RUB;",
            "02/02/2024;Наличные;Еда;-2500.2;RUB;-2500.2;RUB;",
        ])
        #expect(file.expenses.map(\.amountMinor) == [250_000, 250_020])
    }

    @Test func readsQuotedAmountsWithCommaThousandsAndQuotedNotes() throws {
        let file = try F.parse([
            F.header,
            #"13/07/2026,Cash,Food,"-3,960","THB","-3,960",THB,"Кофе ""Brand"", с собой""#,
            "14/07/2026,Cash,Food,\"-1,250.75\",THB,\"-1,250.75\",THB,\"две\nстроки\"",
            "15/07/2026,Cash,Food,-12.5,THB,-12.5,THB,",
        ])

        #expect(file.expenses.map(\.amountMinor) == [396_000, 125_075, 1250])
        #expect(file.expenses.map(\.note) == [#"Кофе "Brand", с собой"#, "две\nстроки", ""])
        // Перевод строки внутри кавычек — та же запись; следующая начинается на строку ниже.
        #expect(file.expenses.map(\.line) == [2, 3, 5])
    }

    @Test func readsDecimalCommaThousandsDotNumbers() throws {
        let file = try F.parse([
            "date;account;category;amount;currency;converted amount;currency;description",
            "21.03.2024;Konto;Essen;-1.250,00;EUR;-1.250,00;EUR;",
            "22.03.2024;Konto;Essen;-1.250;EUR;-1.250;EUR;",
        ])
        #expect(file.expenses.map(\.amountMinor) == [125_000, 125_000])
        #expect(file.expenses.map(\.day) == [F.day(2024, 3, 21), F.day(2024, 3, 22)])
    }

    @Test func prefersConvertedAmountInMainCurrencyAndRoundsToHundredths() throws {
        let file = try F.parse([
            F.header,
            "21/03/2024,Card,Travel,-10,USD,-32.5671,BYN,",
            "21/03/2024,Card,Travel,-10,USD,-3.334,BYN,",
            "21/03/2024,Cash,Food,-7,BYN,,,",
        ])

        #expect(file.expenses.map(\.amountMinor) == [3257, 333, 700])
        #expect(file.expenses.map(\.currencyCode) == ["BYN", "BYN", "BYN"])
    }

    @Test func listsDistinctCurrenciesOfExpenses() throws {
        let file = try F.parse([
            "date,account,category,amount,currency,description",
            "21/03/2024,Card,Travel,-10,usd,",
            "22/03/2024,Cash,Food,-7,EUR,",
            "23/03/2024,Cash,Food,-7,EUR,",
        ])
        #expect(file.currencyCodes == ["EUR", "USD"])
    }

    @Test func translatedHeaderIsRecognisedByColumnLayout() throws {
        let file = try F.parse([
            "дата;счёт;категория;сумма;валюта;сумма в основной валюте;валюта;описание",
            "21/03/2024;Наличные;Еда;-10;BYN;-10;BYN;Обед",
        ])
        #expect(file.expenses.map(\.note) == ["Обед"])
    }

    // MARK: - Доходы и переводы

    @Test func skipsAndCountsIncomeTransfersAndOpeningBalances() throws {
        let file = try F.parse([
            F.header,
            "01/09/2026,Карта,Initial balance 'Карта',1 000.00,RUB,1 000.00,RUB,",
            "02/09/2026,Наличные,To 'Карта',-5 000.00,RUB,-5 000.00,RUB,",
            "02/09/2026,Карта,From 'Наличные',5 000.00,RUB,5 000.00,RUB,",
            "03/09/2026,Карта,Зарплата,+1500,RUB,+1500,RUB,",
            "03/09/2026,Cash,From grandma,50.00,RUB,50.00,RUB,Подарок",
            "04/09/2026,Cash,Toys,-20.00,RUB,-20.00,RUB,Lego",
            "04/09/2026,Cash,Ноль,0,RUB,0,RUB,",
        ])

        #expect(file.expenses.map(\.category) == ["Toys"])
        #expect(file.transferCount == 3)
        #expect(file.incomeCount == 3)
    }

    @Test func fileWithoutExpensesIsRejected() {
        #expect(throws: MonefyCSVError.noExpenses) {
            try F.parse([F.header, "03/09/2026,Card,Salary,1500,RUB,1500,RUB,"])
        }
    }

    @Test func skipsBlankAndDelimiterOnlyRows() throws {
        let file = try F.parse([F.header, "21/03/2024,Cash,Food,-10,BYN,-10,BYN,", "", ",,,,,,,"])
        #expect(file.expenses.count == 1)
    }

    // MARK: - Даты

    @Test(arguments: [
        ("21.03.2024", MonefyFixture.day(2024, 3, 21)),
        ("2024-03-21", MonefyFixture.day(2024, 3, 21)),
        ("1/2/2024", MonefyFixture.day(2024, 2, 1)),
        (" 05-11-2025 ", MonefyFixture.day(2025, 11, 5)),
    ])
    func readsDateFormats(raw: String, expected: MonefyCSV.Day) throws {
        let file = try F.parse([F.header, "\(raw),Cash,Food,-10,BYN,-10,BYN,"], dayFirst: true)
        #expect(file.expenses.first?.day == expected)
    }

    @Test func ambiguousDatesFollowDeviceOrderAndUnambiguousOnesWin() throws {
        let ambiguous = [F.header, "1/2/2024,Cash,Food,-10,BYN,-10,BYN,"]
        #expect(try F.parse(ambiguous, dayFirst: true).expenses.first?.day == F.day(2024, 2, 1))
        #expect(try F.parse(ambiguous, dayFirst: false).expenses.first?.day == F.day(2024, 1, 2))

        // Одна дата с днём больше 12 решает порядок для всего файла.
        let monthFirst = try F.parse(ambiguous + ["1/13/2024,Cash,Food,-10,BYN,-10,BYN,"], dayFirst: true)
        #expect(monthFirst.expenses.map(\.day) == [F.day(2024, 1, 2), F.day(2024, 1, 13)])
    }

    @Test(arguments: ["31/02/2024", "2024/13/01", "21/03/24", "вчера", "", "13/13/2024"])
    func badDateNamesTheLine(raw: String) {
        #expect(throws: MonefyCSVError.badRow(line: 3, .badDate)) {
            try F.parse([F.header, "01/03/2024,Cash,Food,-10,BYN,-10,BYN,", "\(raw),Cash,Food,-10,BYN,-10,BYN,"])
        }
    }

    @Test func dateContradictingFileOrderIsBad() {
        // 21/03 задаёт «день первым», тогда 3/21 — месяц 21.
        #expect(throws: MonefyCSVError.badRow(line: 3, .badDate)) {
            try F.parse([F.header, "21/03/2024,Cash,Food,-10,BYN,-10,BYN,", "3/21/2024,Cash,Food,-10,BYN,-10,BYN,"])
        }
    }

    @Test func dayOrderOfLocales() {
        #expect(!MonefyCSV.isDayFirst(in: Locale(identifier: "en_US")))
        #expect(MonefyCSV.isDayFirst(in: Locale(identifier: "ru_RU")))
        #expect(MonefyCSV.isDayFirst(in: Locale(identifier: "en_GB")))
    }

    // MARK: - Суммы

    @Test(arguments: [
        ("-10", nil, Int64(1000), true),
        ("+5000", nil, 500_000, false),
        ("−4.6", nil, 460, true),
        ("-1,250", nil, 125_000, true),
        ("-1,250", ".", 125_000, true),
        ("-1,250", ",", 125, true),
        ("-1.250", ",", 125_000, true),
        ("-0,5", nil, 50, true),
        ("-.75", ".", 75, true),
        ("-1,234,567.891", nil, 123_456_789, true),
        ("-12.345", ".", 1235, true),
        ("-12.344", ".", 1234, true),
    ] as [(String, Character?, Int64, Bool)])
    func parsesAmount(raw: String, decimal: Character?, minor: Int64, isNegative: Bool) throws {
        #expect(try MonefyCSV.parseAmount(raw, decimalSeparator: decimal) == .init(isNegative: isNegative, minor: minor))
    }

    @Test(arguments: ["", "-", "abc", "-1,2,3", "-12,34.5,6", "-1.250.5", "-12.", "--5", "-1e5", "-1 2a"])
    func rejectsMalformedAmount(raw: String) {
        #expect(throws: MonefyCSVError.RowProblem.badAmount) {
            try MonefyCSV.parseAmount(raw, decimalSeparator: ".")
        }
    }

    @Test func decimalSeparatorIsDetectedFromUnambiguousAmounts() {
        #expect(MonefyCSV.decimalSeparator(in: ["-10", "-1,250", "-4.60"]) == ".")
        #expect(MonefyCSV.decimalSeparator(in: ["-1.250", "-4,6"]) == ",")
        #expect(MonefyCSV.decimalSeparator(in: ["-1.250.000"]) == ",")
        #expect(MonefyCSV.decimalSeparator(in: ["-1,250.00"]) == ".")
        #expect(MonefyCSV.decimalSeparator(in: ["-10", "-1,250"]) == nil)
    }

    @Test func badAmountNamesTheLine() {
        #expect(throws: MonefyCSVError.badRow(line: 2, .badAmount)) {
            try F.parse([F.header, "21/03/2024,Cash,Food,десять,BYN,десять,BYN,"])
        }
    }

    @Test func amountOverLimitIsRejected() throws {
        #expect(throws: MonefyCSVError.badRow(line: 2, .amountTooLarge)) {
            try F.parse([F.header, "21/03/2024,Cash,Food,-100000000000,BYN,-100000000000,BYN,"])
        }
        #expect(throws: MonefyCSVError.badRow(line: 2, .amountTooLarge)) {
            try F.parse([F.header, "21/03/2024,Cash,Food,-99999999999999999999,BYN,-99999999999999999999,BYN,"])
        }
        #expect(try F.parse([F.header, "21/03/2024,Cash,Food,-99999999999.99,BYN,-99999999999.99,BYN,"])
            .expenses.first?.amountMinor == Money.maxAmountMinor)
    }

    // MARK: - Не файл Monefy

    @Test func rejectsFilesThatAreNotMonefyExports() {
        let notMonefy: [Data] = [
            Data(),
            Data([0xFF, 0xFE, 0x00, 0xD8]),
            F.data(["{\"formatVersion\": 2}"]),
            F.data(["Дата,Сумма,Категория", "21.03.2024,-10,Еда"]),
        ]
        for data in notMonefy {
            #expect(throws: MonefyCSVError.notMonefyFile) { try MonefyCSV.parse(data) }
        }
    }

    @Test func shortRowIsMissingData() {
        #expect(throws: MonefyCSVError.badRow(line: 3, .missingField)) {
            try F.parse([F.header, "21/03/2024,Cash,Food,-10,BYN,-10,BYN,", "21/03/2024,Cash"])
        }
    }
}
