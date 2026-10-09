import SwiftUI

/// Стеклянный сегмент-переключатель (DESIGN.md → «Сегмент периода», §6): капсула 44, активная пилюля 36
/// (бумага 92 % / ночью rgba(255,250,244,.16)) едет через `matchedGeometryEffect`.
/// VoiceOver: контейнер с подписью (`title`), пункты — кнопки с трейтом `.isSelected`.
struct GlassSegmentedControl<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: LocalizedStringKey
        /// Иконка вместо текста (переключатель видов в статистике); `title` остаётся подписью VoiceOver.
        var systemImage: String?
    }

    let title: LocalizedStringKey
    @Binding var selection: Value
    let items: [Item]

    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.value) { item in
                segment(item)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .frame(minHeight: Theme.Size.segment)
        .glassEffect(.regular, in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .sensoryFeedback(Haptic.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func segment(_ item: Item) -> some View {
        let isSelected = item.value == selection
        return Button {
            withAnimation(Motion.animation(Motion.segmentPill, reduceMotion: reduceMotion)) {
                selection = item.value
            }
        } label: {
            label(item)
                .typeStyle(.callout)
                .foregroundStyle(isSelected ? Theme.ink : Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.segmentPill)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.segmentPill)
                            .paperShadow(Tokens.Shadow.segmentActive)
                            .matchedGeometryEffect(id: "pill", in: pillNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
    }

    @ViewBuilder
    private func label(_ item: Item) -> some View {
        if let systemImage = item.systemImage {
            Image(systemName: systemImage)
        } else {
            Text(item.title)
        }
    }
}

#if DEBUG
private struct SegmentDemo: View {
    enum Period: Hashable { case day, week, month, year, custom }
    enum View4: Hashable { case tiles, strips, sun, ring }

    @State private var period = Period.month
    @State private var view = View4.strips

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            GlassSegmentedControl(title: "Период", selection: $period, items: [
                .init(value: .day, title: "День"),
                .init(value: .week, title: "Неделя"),
                .init(value: .month, title: "Месяц"),
                .init(value: .year, title: "Год"),
                .init(value: .custom, title: "Свой"),
            ])
            GlassSegmentedControl(title: "Вид", selection: $view, items: [
                .init(value: .tiles, title: "Плитки", systemImage: "square.grid.2x2.fill"),
                .init(value: .strips, title: "Полосы", systemImage: "text.alignleft"),
                .init(value: .sun, title: "Солнце", systemImage: "circle.dashed"),
                .init(value: .ring, title: "Кольцо", systemImage: "circle.circle"),
            ])
            .frame(width: 200)
        }
    }
}

#Preview("Сегмент") {
    ThemePreview { SegmentDemo() }
}
#endif
