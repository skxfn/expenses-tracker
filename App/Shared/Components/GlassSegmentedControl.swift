import SwiftUI

/// Стеклянный сегмент-переключатель (DESIGN.md → «Сегмент периода», §6): капсула 44, активная пилюля 36
/// (белая 92 % / ночью rgba(255,250,244,.16)) едет через `matchedGeometryEffect`; при Reduce Motion — только opacity.
/// Цель касания пункта — вся высота капсулы 44. Текст ограничен AX1: длинная подпись ужимается,
/// крупнее — Large Content Viewer (долгое нажатие).
/// VoiceOver: контейнер с подписью (`title`), пункты — кнопки с трейтом `.isSelected`.
struct GlassSegmentedControl<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: LocalizedStringKey
        /// Иконка вместо текста (переключатель видов в статистике); `title` остаётся подписью VoiceOver.
        var systemImage: String?
        /// Подпись VoiceOver, если видимый текст — знак («Ƃ» → «Знак рубля»).
        var accessibilityTitle: LocalizedStringKey?
    }

    let title: LocalizedStringKey
    @Binding var selection: Value
    let items: [Item]

    /// Пять пунктов на AX1 шире капсулы («Неделя» ≈ 90 pt при 56 доступных): подпись ужимается до 60 %, а не обрезается.
    private static var minimumLabelScale: CGFloat { 0.6 }

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
                .minimumScaleFactor(Self.minimumLabelScale)
                .padding(.horizontal, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.segmentPill)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.segmentPill)
                            .paperShadow(Tokens.Shadow.segmentActive)
                            .matchedGeometryEffect(id: pillID(item), in: pillNamespace)
                    }
                }
                // Пилюля 36, а нажимается вся высота стеклянной капсулы 44.
                .frame(minHeight: Theme.Size.segment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityTitle ?? item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            largeContent(item)
        }
    }

    /// Общий id — пилюля едет к выбранному пункту. При Reduce Motion у каждого пункта свой id:
    /// геометрия не связывается, старая пилюля гаснет, новая проявляется (только opacity).
    private func pillID(_ item: Item) -> AnyHashable {
        reduceMotion ? AnyHashable(item.value) : AnyHashable("pill")
    }

    @ViewBuilder
    private func label(_ item: Item) -> some View {
        if let systemImage = item.systemImage {
            Image(systemName: systemImage)
        } else {
            Text(item.title)
        }
    }

    /// Large Content Viewer: иконка вместе с подписью, текст — как на сегменте (знак рубля — через `typeStyle`).
    @ViewBuilder
    private func largeContent(_ item: Item) -> some View {
        if let systemImage = item.systemImage {
            Label(item.title, systemImage: systemImage)
        } else {
            Text(item.title)
                .typeStyle(.callout)
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
