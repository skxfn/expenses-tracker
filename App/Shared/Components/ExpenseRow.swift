import SwiftUI
import ExpenseCore

/// Снимок траты для строки (лента, календарь, топ статистики, «только что записанные»).
/// Свойства удалённой модели потом читать нельзя (ловушка AGENTS.md), поэтому всё копируется сразу.
struct ExpenseRowData: Identifiable, Hashable {
    let id: UUID
    /// Иконка листа: подкатегории, если трата в подкатегории (канон ленты, INTEGRATION §8 п. 6).
    let iconName: String
    /// Тон категории верхнего уровня; `nil` — «Без категории».
    let tone: GouacheTone?
    /// Заголовок: заметка, без неё — имя листа (`feed.row.noNote`), без категории — `feed.row.noCategory`.
    let title: String
    /// «Категория · Подкатегория», «Категория» или `nil`.
    let subtitle: String?
    let amountMinor: Int64
    let date: Date

    init(_ expense: Expense) {
        let leaf = expense.category
        let group = leaf?.parent ?? leaf
        let note = expense.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let uncategorized = String(localized: "feed.row.noCategory")

        id = expense.id
        iconName = leaf?.iconName ?? CategoryPaint.uncategorizedIconName
        tone = group.flatMap { GouacheTone(mainHex: $0.colorHex) }
        amountMinor = expense.amountMinor
        date = expense.date

        let path: String? = switch (group, leaf) {
        case let (group?, leaf?) where group.id != leaf.id: "\(group.name) · \(leaf.name)"
        case let (group?, _): group.name
        default: nil
        }
        if !note.isEmpty {
            title = note
            subtitle = path ?? uncategorized
        } else if let leaf {
            // Без заметки: заголовок — имя листа, подпись — категория (`feed.row.noNote`).
            title = leaf.name
            subtitle = leaf.parent?.name
        } else {
            title = uncategorized
            subtitle = nil
        }
    }
}

/// Строка траты 60: плашка 36 (tint + deep-иконка), заголовок SF 17, подпись SF 13, сумма Unbounded 15 без «Br».
/// Один элемент VoiceOver; действия «Удалить» / «Повторить сегодня» добавляет экран.
struct ExpenseRow: View {
    let data: ExpenseRowData
    @Environment(\.moneyFormatter) private var money

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            CategoryPlaque(iconName: data.iconName, tone: data.tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: data.title)
                    .typeStyle(.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let subtitle = data.subtitle {
                    Text(verbatim: subtitle)
                        .typeStyle(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            AmountText(
                text: money.string(fromMinor: data.amountMinor, style: .plain),
                value: Double(data.amountMinor),
                size: .inline
            )
        }
        .frame(minHeight: Theme.Size.feedRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    /// `feed.row.a11y`: «Обед, Кафе, Обеды, 44,70 рубля» — без «·».
    private var accessibilityText: String {
        let parts = [data.title, data.subtitle?.replacingOccurrences(of: " · ", with: ", "), spokenAmount]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    private var spokenAmount: String {
        let whole = data.amountMinor / Money.minorUnitsPerMajor
        let cents = data.amountMinor % Money.minorUnitsPerMajor
        return cents == 0
            ? L10n.format("a11y.money", whole)
            : L10n.format("a11y.money.fraction", money.string(fromMinor: data.amountMinor, style: .plain))
    }
}
