import SwiftUI

/// Стеклянный сегмент-переключатель (DESIGN.md → «Сегмент периода», §6): капсула 44, активная пилюля 36
/// (белая 92 % / ночью rgba(255,250,244,.16)) едет через `matchedGeometryEffect`; при Reduce Motion — только opacity.
/// Цель касания пункта — вся высота капсулы 44. Текст ограничен AX1; если ряд не помещается, кегль уменьшается
/// у всех подписей сразу (`labelSizes`), а не у каждой своей мерой; крупнее — Large Content Viewer (долгое нажатие).
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Ряд с первым кеглем, при котором помещаются все подписи: один размер на все пункты.
        ViewThatFits(in: .horizontal) {
            ForEach(labelSizes, id: \.self) { size in
                segments(labelSize: size)
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

    /// Кегли подписей от текущего (не крупнее AX1) вниз до размера по умолчанию: на нём ряд — как был,
    /// мельче не уменьшаем (дальше каждая подпись ужимается `minimumLabelScale`).
    private var labelSizes: [DynamicTypeSize] {
        let current = min(dynamicTypeSize, .accessibility1)
        return DynamicTypeSize.allCases
            .filter { $0 <= current && ($0 >= .large || $0 == current) }
            .reversed()
    }

    private func segments(labelSize: DynamicTypeSize) -> some View {
        SegmentRow {
            ForEach(items, id: \.value) { item in
                segment(item, labelSize: labelSize)
            }
        }
    }

    /// Кегль меняется только у подписи: у кнопки остаётся размер окружения, и Large Content Viewer работает.
    private func segment(_ item: Item, labelSize: DynamicTypeSize) -> some View {
        let isSelected = item.value == selection
        return Button {
            withAnimation(Motion.animation(Motion.segmentPill, reduceMotion: reduceMotion)) {
                selection = item.value
            }
        } label: {
            label(item)
                .typeStyle(.callout)
                .dynamicTypeSize(labelSize)
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

/// Ряд пунктов: поровну, пока подписи помещаются в равные доли (как `HStack` из растягивающихся пунктов);
/// иначе пункт с длинной подписью получает свою ширину, остальные делят остаток. Идеальная ширина — сумма
/// идеальных ширин пунктов: по ней `ViewThatFits` выбирает общий кегль. Не помещается и она — поровну.
private struct SegmentRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideals.reduce(0, +)
        let height = zip(subviews, Self.widths(ideals, total: width))
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        var x = bounds.minX
        for (subview, width) in zip(subviews, Self.widths(ideals, total: bounds.width)) {
            subview.place(
                at: CGPoint(x: x + width / 2, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width
        }
    }

    /// Доли ряда: пункты, чья подпись шире равной доли остатка, получают свою ширину, остальные — поровну.
    static func widths(_ ideals: [CGFloat], total: CGFloat) -> [CGFloat] {
        guard !ideals.isEmpty else { return [] }
        let equal = total / CGFloat(ideals.count)
        guard ideals.reduce(0, +) <= total else { return ideals.map { _ in equal } }
        var isFixed = ideals.map { _ in false }
        var remaining = total
        var freeCount = ideals.count
        var isChanged = true
        while isChanged, freeCount > 0 {
            isChanged = false
            let share = remaining / CGFloat(freeCount)
            for index in ideals.indices where !isFixed[index] && ideals[index] > share {
                isFixed[index] = true
                remaining -= ideals[index]
                freeCount -= 1
                isChanged = true
            }
        }
        let share = freeCount > 0 ? remaining / CGFloat(freeCount) : 0
        return ideals.indices.map { isFixed[$0] ? ideals[$0] : share }
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
