import Foundation
import Testing
@testable import ExpenseCore

struct AmountInputTests {
    @Test(arguments: [
        ("12,5", "12,5"),
        ("12.50", "12,50"),
        ("007", "7"),
        ("0", "0"),
        ("00", "0"),
        (",", "0,"),
        (".5", "0,5"),
        ("0,05", "0,05"),
        ("1 200", "1200"),
        ("-5", "5"),
        ("12,3,4", "12,34"),
        ("1a2b", "12"),
        ("", "")
    ])
    func sanitizesTypedText(input: String, expected: String) {
        let result = AmountInput.sanitize(input)
        #expect(result.text == expected)
        #expect(!result.droppedFractionDigits)
    }

    @Test func dropsThirdFractionDigit() {
        let result = AmountInput.sanitize("12,505")
        #expect(result.text == "12,50")
        #expect(result.droppedFractionDigits)
    }

    @Test func limitsIntegerDigits() {
        let result = AmountInput.sanitize(String(repeating: "9", count: 20) + ",99")
        #expect(result.text == String(repeating: "9", count: AmountInput.maxIntegerDigits) + ",99")
        #expect(Money.minor(fromInput: result.text) == AmountInput.maxMinor)
    }

    @Test(arguments: [
        ("", Int64(5), Int64(500)),
        ("0,", 10, 1_000),
        ("12,50", 5, 1_750),
        ("12,", 100, 11_200),
        ("1200", 50, 125_000)
    ])
    func quickAmountAddsToEntered(text: String, units: Int64, expected: Int64) {
        #expect(AmountInput.adding(units, to: text) == expected)
    }

    @Test func quickAmountRejectsOverflow() {
        let max = String(repeating: "9", count: AmountInput.maxIntegerDigits)
        #expect(AmountInput.adding(5, to: max) == nil)
        #expect(AmountInput.adding(.max, to: "1") == nil)
        #expect(AmountInput.adding(0, to: "1") == nil)
    }
}

struct EntryDateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Minsk")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func todayAndYesterdayResolveAtSaveTime() {
        let now = date(10, 0, 1)
        #expect(EntryDate.today.resolved(now: now, calendar: calendar) == now)
        #expect(EntryDate.yesterday.resolved(now: now, calendar: calendar) == date(9, 0, 1))
    }

    @Test func pickedDayBecomesSegment() {
        let now = date(10, 18, 30)
        #expect(EntryDate.picked(date(10, 0), now: now, calendar: calendar) == .today)
        #expect(EntryDate.picked(date(9, 0), now: now, calendar: calendar) == .yesterday)
        #expect(EntryDate.picked(date(5, 0), now: now, calendar: calendar) == .moment(date(5, 18, 30)))
    }

    @Test func newExpenseFromCalendarKeepsDay() {
        let now = date(10, 9, 15)
        #expect(EntryDate.forNewExpense(on: nil, now: now, calendar: calendar) == .today)
        #expect(EntryDate.forNewExpense(on: date(3, 0), now: now, calendar: calendar) == .moment(date(3, 9, 15)))
    }

    @Test func editedMomentShowsMatchingSegment() {
        let now = date(10, 20)
        #expect(EntryDate.moment(date(10, 8)).segment(now: now, calendar: calendar) == .today)
        #expect(EntryDate.moment(date(9, 8)).segment(now: now, calendar: calendar) == .yesterday)
        #expect(EntryDate.moment(date(5, 8)).segment(now: now, calendar: calendar) == .other(date(5, 8)))
        #expect(EntryDate.moment(date(5, 8)).resolved(now: now, calendar: calendar) == date(5, 8))
    }
}

struct ExpenseDraftTests {
    private let formatter = MoneyFormatter(currencyCode: "BYN", locale: Locale(identifier: "ru_RU"))

    @Test func quickAmountRewritesFieldWithEditingString() {
        var draft = ExpenseDraft(amountText: "12,5")
        let first = draft.addQuickAmount(5, formatter: formatter)
        #expect(first)
        #expect(draft.amountText == "17,50")
        let second = draft.addQuickAmount(100, formatter: formatter)
        #expect(second)
        #expect(draft.amountText == "117,50")

        var empty = ExpenseDraft()
        empty.addQuickAmount(20, formatter: formatter)
        #expect(empty.amountText == "20")
        #expect(empty.amountMinor == 2_000)
    }

    @Test func quickAmountOverflowKeepsField() {
        let max = String(repeating: "9", count: AmountInput.maxIntegerDigits)
        var draft = ExpenseDraft(amountText: max)
        let added = draft.addQuickAmount(5, formatter: formatter)
        #expect(!added)
        #expect(draft.amountText == max)
    }

    @Test func anotherOneResetsAllButDate() {
        let category = UUID()
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var draft = ExpenseDraft(amountText: "5", categoryID: category, date: .moment(day), note: "такси")
        draft.resetForNextExpense()
        #expect(draft == ExpenseDraft(date: .moment(day)))
    }

    @Test func newExpenseIsModifiedByAmountOrNote() {
        let initial = ExpenseDraft()
        #expect(!ExpenseDraft(categoryID: UUID(), date: .yesterday).hasUnsavedChanges(comparedTo: initial, isNew: true))
        #expect(!ExpenseDraft(note: "  ").hasUnsavedChanges(comparedTo: initial, isNew: true))
        #expect(ExpenseDraft(amountText: "0").hasUnsavedChanges(comparedTo: initial, isNew: true))
        #expect(ExpenseDraft(note: "такси").hasUnsavedChanges(comparedTo: initial, isNew: true))
    }

    @Test func editIsModifiedOnlyByRealChanges() {
        let category = UUID()
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let initial = ExpenseDraft(amountText: "12,5", categoryID: category, date: .moment(day), note: "Обед")

        var same = initial
        same.amountText = "12,50"
        same.note = "Обед "
        #expect(!same.hasUnsavedChanges(comparedTo: initial, isNew: false))

        var changed = initial
        changed.categoryID = nil
        #expect(changed.hasUnsavedChanges(comparedTo: initial, isNew: false))
        changed = initial
        changed.date = .today
        #expect(changed.hasUnsavedChanges(comparedTo: initial, isNew: false))
        changed = initial
        changed.amountText = ""
        #expect(changed.hasUnsavedChanges(comparedTo: initial, isNew: false))
    }
}

struct EntryBatchTests {
    @Test func countsAndSumsEntries() {
        var batch = EntryBatch()
        let first = UUID()
        let second = UUID()
        batch.append(id: first, amountMinor: 1_250)
        batch.append(id: second, amountMinor: 900)
        #expect(batch.count == 2)
        #expect(batch.totalMinor == 2_150)
        #expect(batch.excluding([first]).totalMinor == 900)

        batch.keep { $0 == second }
        #expect(batch.entries.map(\.id) == [second])
    }

    @Test func totalSaturatesInsteadOfOverflow() {
        var batch = EntryBatch()
        batch.append(id: UUID(), amountMinor: .max)
        batch.append(id: UUID(), amountMinor: 1)
        #expect(batch.totalMinor == .max)
    }
}

struct SwatchRowTests {
    private struct Item: Identifiable, Equatable {
        let id: Int
    }

    private let frequent = (1...6).map(Item.init)

    @Test func pinnedReplacesLastFrequent() {
        let row = SwatchRow.compose(frequent: frequent, pinned: Item(id: 9))
        #expect(row.map(\.id) == [1, 2, 3, 4, 5, 9])
    }

    @Test func pinnedAmongFrequentKeepsRow() {
        #expect(SwatchRow.compose(frequent: frequent, pinned: Item(id: 3)) == frequent)
        #expect(SwatchRow.compose(frequent: frequent, pinned: nil) == frequent)
    }

    @Test func shortRowAppendsPinned() {
        let row = SwatchRow.compose(frequent: [Item(id: 1)], pinned: Item(id: 9))
        #expect(row.map(\.id) == [1, 9])
        #expect(SwatchRow.compose(frequent: [Item](), pinned: Item(id: 9)).map(\.id) == [9])
    }
}
