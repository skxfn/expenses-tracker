#if DEBUG
import SwiftUI

/// Эталон «жидкой линзы» системных элементов для сверки линзы календаря: `Picker(.segmented)` на 4 и 5 сегментов,
/// `Toggle` и системный `TabView` (его выделение — та же линза). Под таб-баром — клетки heat, чтобы было видно
/// преломление. Открыть: `-debugShowcase nativeLens`; касания для записи видео — XCUITest по идентификаторам.
struct NativeLensReference: View {
    private static let periods = ["День", "Неделя", "Месяц", "Год"]
    private static let ranges = ["1", "2", "3", "4", "5"]

    @State private var tab = 0
    @State private var period = 0
    @State private var range = 0
    @State private var isOn = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Траты", systemImage: "house", value: 0) { page }
            Tab("Календарь", systemImage: "calendar", value: 1) { page }
            Tab("Статистика", systemImage: "chart.pie", value: 2) { page }
            Tab("Настройки", systemImage: "gearshape", value: 3) { page }
        }
        .tint(Theme.ink)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Picker("Период", selection: $period) {
                ForEach(Self.periods.indices, id: \.self) { Text(verbatim: Self.periods[$0]).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("seg4")

            Picker("Диапазон", selection: $range) {
                ForEach(Self.ranges.indices, id: \.self) { Text(verbatim: Self.ranges[$0]).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("seg5")

            Toggle(isOn: $isOn) { Text(verbatim: "Переключатель") }
                .accessibilityIdentifier("toggle")

            Spacer(minLength: 0)
            heatGrid
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xl)
        .ignoresSafeArea(.container, edges: .bottom)
        .background { AuraBackground(tones: [.kobalt, .ametist]).ignoresSafeArea() }
    }

    /// Клетки как в календаре — под таб-баром, для преломления.
    private var heatGrid: some View {
        Grid(horizontalSpacing: CalendarMetrics.gridGap, verticalSpacing: CalendarMetrics.gridGap) {
            ForEach(0..<3, id: \.self) { week in
                GridRow {
                    ForEach(0..<7, id: \.self) { weekday in
                        let level = (week * 7 + weekday * 3) % 5
                        RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
                            .fill(Theme.heat(level))
                            .frame(height: Theme.Size.calendarCell)
                            .overlay(alignment: .topLeading) {
                                Text(verbatim: "\(week * 7 + weekday + 1)")
                                    .typeStyle(.footnoteStrong)
                                    .foregroundStyle(Theme.heatDigits(level))
                                    .padding(CalendarMetrics.cellPadding)
                            }
                    }
                }
            }
        }
    }
}
#endif
