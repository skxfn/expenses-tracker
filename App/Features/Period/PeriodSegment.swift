import SwiftUI

/// Сегмент периода «День · Неделя · Месяц · Год · Свой» (DESIGN.md → Navigation, §6) на `GlassSegmentedControl`.
/// «Свой» без выбранного диапазона и повторный тап по активному «Свой» открывают шит «Период»:
/// пилюля переезжает только после выбора диапазона. Поля экрана задаёт экран.
struct PeriodSegment: View {
    let selection: PeriodSelection

    var body: some View {
        GlassSegmentedControl(
            title: "period.segment.a11y",
            selection: Binding(get: { selection.mode }, set: { selection.select($0) }),
            items: PeriodMode.allCases.map { .init(value: $0, title: $0.titleKey) }
        )
    }
}
