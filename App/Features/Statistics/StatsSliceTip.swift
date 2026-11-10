import SwiftUI

/// Стеклянная подсказка среза — одна на все графики статистики («По дням», «Темп», «Привычки», карта года):
/// строки SF 15/600 (подпись secondary, значение графитом) в стекле `glass-in`, капсула 36; в несколько строк —
/// скруглённый прямоугольник того же радиуса, как заголовок дня ленты. С действием — шеврон и касание: открывает
/// список трат среза; стекло тогда с `.interactive()` — у него свой отклик нажатия.
/// Подсказка только для глаз: VoiceOver получает то же через элементы графика (подписи, действия, adjustable).
struct StatsSliceTip<Content: View>: View {
    /// `nil` — без шеврона и касания (у среза нет трат или подсказка ещё не закреплена).
    var action: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Size.dayHeader / 2, style: .continuous)
        if let action {
            Button(action: action) {
                label.glass(.key, in: shape)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        } else {
            label
                .glass(.inContent, in: shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.sm) {
            content()
            if action != nil {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.graphic)
            }
        }
        .typeStyle(.callout)
        .padding(.horizontal, Theme.Spacing.md + Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(minHeight: Theme.Size.dayHeader)
        .contentShape(Rectangle())
    }
}

/// Закреплённый выбор на графике: подсказка остаётся у выбранного и после того, как палец поднят.
/// Скраббинг (`chartXSelection`) — `track`: закрепляется значение под пальцем, касание закреплённого без движения
/// снимает закрепление. Касания плиток и клеток — `toggle`.
struct StatsPin<Value: Equatable>: Equatable {
    private(set) var value: Value?
    /// Касание началось на закреплённом и не сдвинулось — по отпусканию закрепление снимается.
    private var touchUnpins = false

    mutating func track(from old: Value?, to new: Value?) {
        switch (old, new) {
        case (nil, let current?):
            touchUnpins = current == value
            value = current
        case (let previous?, let current?) where previous != current:
            touchUnpins = false
            value = current
        case (_?, nil):
            if touchUnpins { value = nil }
            touchUnpins = false
        default:
            break
        }
    }

    mutating func toggle(_ new: Value) {
        value = value == new ? nil : new
    }

    /// Выбор без касания: шаг VoiceOver (adjustable).
    mutating func select(_ new: Value) {
        value = new
        touchUnpins = false
    }

    mutating func reset() {
        value = nil
        touchUnpins = false
    }
}

/// Строка подсказки: подпись secondary и значение графитом («Сегодня  57,20 ⃅»).
struct StatsTipLine: View {
    let title: String
    let value: String
    var valueColor: Color = Theme.ink

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(verbatim: title)
                .foregroundStyle(Theme.secondary)
            Text(verbatim: value)
                .foregroundStyle(valueColor)
        }
        .lineLimit(1)
    }
}
