#if DEBUG
import SwiftUI
import ExpenseCore

/// Демо-данные спайков (иллюстрация макета `01-home`, не спецификация).
enum SpikeSamples {
    struct Row: Identifiable {
        let id = UUID()
        let note: String
        let category: String
        let icon: String
        let tone: GouacheTone?
        let amount: String
    }

    struct Day: Identifiable {
        let id = UUID()
        let title: String
        let date: String
        let total: String
        let rows: [Row]
    }

    static let days: [Day] = [
        Day(title: "Сегодня", date: "· чт, 8 окт", total: "57,20", rows: [
            Row(note: "Обед", category: "Кафе · Обеды", icon: "fork-knife-fill", tone: .abrikos, amount: "44,70"),
            Row(note: "Молоко, хлеб, яблоки", category: "Продукты · Супермаркет", icon: "shopping-cart-1-fill", tone: .shalfey, amount: "12,50"),
        ]),
        Day(title: "Вчера", date: "· ср, 7 окт", total: "31,00", rows: [
            Row(note: "Такси до дома", category: "Транспорт", icon: "car-fill", tone: .kobalt, amount: "9,00"),
            Row(note: "Овощи на неделю", category: "Продукты · Рынок", icon: "basket-fill", tone: .shalfey, amount: "22,00"),
        ]),
        Day(title: "Вт", date: "6 окт", total: "64,10", rows: [
            Row(note: "Кино", category: "Развлечения", icon: "movie-fill", tone: .ametist, amount: "18,00"),
            Row(note: "Интернет", category: "Связь", icon: "wifi-fill", tone: .tseruleum, amount: "25,00"),
            Row(note: "Аптека", category: "Здоровье", icon: "capsule-fill", tone: .kinovar, amount: "11,10"),
            Row(note: "Без категории", category: "Без категории", icon: CategoryPaint.uncategorizedIconName, tone: nil, amount: "10,00"),
        ]),
        Day(title: "Пн", date: "5 окт", total: "48,30", rows: [
            Row(note: "Подписка на музыку", category: "Подписки", icon: "repeat-fill", tone: .ultramarin, amount: "8,30"),
            Row(note: "Продукты", category: "Продукты", icon: "basket-fill", tone: .shalfey, amount: "40,00"),
        ]),
    ]
}

/// Строка ленты для спайков: плашка 36 + заметка SF 17 + «Категория · Подкатегория» SF 13 + сумма Unbounded 15.
struct SpikeFeedRow: View {
    let row: SpikeSamples.Row

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            CategoryPlaque(iconName: row.icon, tone: row.tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.note).typeStyle(.body).foregroundStyle(Theme.ink).lineLimit(1)
                Text(verbatim: row.category).typeStyle(.footnote).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            AmountText(text: row.amount, value: 0, size: .inline)
        }
        .frame(minHeight: Theme.Size.feedRow)
        .accessibilityElement(children: .combine)
    }
}

/// Липкий заголовок дня: стеклянная капсула 36 (`glass-in`), «Сегодня · чт, 8 окт» и сумма дня Unbounded 600.
struct SpikeDayHeader: View {
    let day: SpikeSamples.Day

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: day.title).typeStyle(.callout).foregroundStyle(Theme.ink)
            Text(verbatim: day.date).typeStyle(.callout).foregroundStyle(Theme.secondary)
            Spacer()
            AmountText(text: day.total, value: 0, size: .inlineStrong)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.Size.dayHeader)
        .glass(.inContent)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Шапка главного для спайков: месяц, ‹ › и ⚙, сегмент периода.
struct SpikeHomeHeader: View {
    @State private var period = 2

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text(verbatim: "Октябрь").typeStyle(.monthTitle).foregroundStyle(Theme.ink)
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                GlassEffectContainer {
                    HStack(spacing: Theme.Spacing.sm) {
                        GlassStepperPair(previousLabel: "Назад", nextLabel: "Вперёд", canGoNext: false, onPrevious: {}, onNext: {})
                        Button("Настройки", systemImage: "gearshape") {}.buttonStyle(.glassCircle())
                    }
                }
            }
            GlassSegmentedControl(title: "Период", selection: $period, items: [
                .init(value: 0, title: "День"), .init(value: 1, title: "Неделя"), .init(value: 2, title: "Месяц"),
                .init(value: 3, title: "Год"), .init(value: 4, title: "Свой"),
            ])
        }
        .padding(.horizontal, Theme.Spacing.screen)
    }
}

/// Итог периода на листе.
struct SpikeSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AmountText(text: "412,30", value: 41_230, size: .total, currency: "Br")
            Text("на **38 Br меньше**, чем в прошлом месяце")
                .typeStyle(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
