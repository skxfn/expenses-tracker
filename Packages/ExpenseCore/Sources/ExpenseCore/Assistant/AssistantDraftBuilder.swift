import Foundation

/// Проверяет ответ модели и собирает черновики: суммы → копейки (без `Double`), ключи → категории,
/// даты → `EntryDate`. Модели не доверяем: всё, что не прошло, становится признаком `DraftIssue`.
public struct AssistantDraftBuilder {
    /// Даты старше — подозрительные (`dateOld`).
    public static let oldDateDays = 365
    /// Длиннее — заметка сокращается по словам.
    public static let noteLimit = 100

    let catalog: AssistantCatalog
    let now: Date
    let calendar: Calendar
    let formatter: MoneyFormatter
    /// Дата трат без даты в ответе.
    let defaultDate: EntryDate

    public init(catalog: AssistantCatalog, now: Date, calendar: Calendar, formatter: MoneyFormatter, defaultDate: EntryDate = .today) {
        self.catalog = catalog
        self.now = now
        self.calendar = calendar
        self.formatter = formatter
        self.defaultDate = defaultDate
    }

    public func build(from json: Data) throws -> AssistantResult {
        guard let response = try? JSONDecoder().decode(AssistantResponse.self, from: json) else {
            throw AssistantError.unreadableResponse
        }
        let receipt = response.receipt.flatMap(receiptSummary)
        let kept = response.expenses.prefix(AssistantPrompt.maxExpenses)
        let items = kept.map { draft(from: $0, receiptDay: receipt?.day) }
        let unparsed = response.unparsed.map(Self.trimmed).filter { !$0.isEmpty }
        guard !items.isEmpty else { throw AssistantError.nothingFound }
        return AssistantResult(items: items, receipt: receipt, unparsed: unparsed, droppedCount: response.expenses.count - kept.count)
    }

    private func draft(from item: AssistantResponse.Item, receiptDay: Date?) -> AssistantDraft {
        var issues: Set<DraftIssue> = []

        let amount = item.amount.flatMap(Self.minor(from:))
        if amount == nil { issues.insert(.amountMissing) }

        let categoryID = item.category.flatMap(catalog.id(forKey:))
        if categoryID == nil { issues.insert(.categoryMissing) }

        let date: EntryDate
        switch item.date.flatMap(day(from:)) ?? receiptDay {
        case .none:
            date = defaultDate
        case .some(let day) where day > today:
            date = .today
            issues.insert(.dateAdjusted)
        case .some(let day):
            if let oldest = calendar.date(byAdding: .day, value: -Self.oldDateDays, to: today), day < oldest {
                issues.insert(.dateOld)
            }
            // Названный день — точный момент, не «Вчера»: черновики, сохранённые после полуночи, не съедут на день.
            date = .moment(EntryDate.combining(day: day, timeOf: now, calendar: calendar))
        }

        let amountText = amount.map {
            AmountInput.sanitize(formatter.editingString(fromMinor: $0), separator: formatter.decimalSeparator).text
        } ?? ""
        return AssistantDraft(
            draft: ExpenseDraft(amountText: amountText, categoryID: categoryID, date: date, note: Self.shortened(item.note)),
            source: Self.trimmed(item.source),
            issues: issues
        )
    }

    /// `nil`, если в «чеке» ни магазина, ни даты, ни итога: модели так отвечают и без чека (скриншот банка),
    /// а чек включает слияние позиций.
    private func receiptSummary(_ receipt: AssistantResponse.Receipt) -> ReceiptSummary? {
        let day = receipt.date.flatMap(day(from:)).flatMap { $0 > today ? nil : $0 }
        let store = receipt.store.map(Self.trimmed).flatMap { $0.isEmpty ? nil : $0 }
        let total = receipt.total.flatMap(Self.minor(from:))
        guard store != nil || day != nil || total != nil else { return nil }
        return ReceiptSummary(store: store, day: day, totalMinor: total)
    }

    private var today: Date { calendar.startOfDay(for: now) }

    /// Начало дня `YYYY-MM-DD` в календаре пользователя.
    func day(from text: String) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let dayNumber = Int(parts[2]) else { return nil }
        let components = DateComponents(year: year, month: month, day: dayNumber)
        guard let date = calendar.date(from: components),
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == dayNumber else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// Сумма из строки модели: «7.50», «7,5», «1 200»; лишние знаки дроби округляются. Больше 0 и не больше предела.
    static func minor(from text: String) -> Int64? {
        let compact = text.filter { !$0.isWhitespace }
        guard let value = Money.minor(fromInput: compact) ?? roundedMinor(compact),
              value > 0, value <= Money.maxAmountMinor else { return nil }
        return value
    }

    /// Лишние знаки дроби («6.160», «12.349999») с округлением. Только цифры и один разделитель:
    /// `Decimal(string:)` молча берёт начало строки («1.200.50» → 1,2, «7abc» → 7).
    private static func roundedMinor(_ text: String) -> Int64? {
        guard text.wholeMatch(of: #/[0-9]+[.,][0-9]+/#) != nil else { return nil }
        return Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
            .flatMap(Money.minor(fromMajor:))
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Заметка не длиннее `noteLimit`: обрезается по границе слова, с многоточием.
    static func shortened(_ note: String) -> String {
        let text = trimmed(note)
        guard text.count > noteLimit else { return text }
        let head = text.prefix(noteLimit - 1)
        let cut = head.lastIndex(of: " ").map { head[..<$0] } ?? head
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }
}
