import SwiftUI

/// Ряд из подвидов с шириной по весам: [Ещё одна] [Сохранить] в пропорции 1 : 1,35 (DESIGN.md → Layout).
/// Высота — по самому высокому (кнопки растут вместе с Dynamic Type).
struct ProportionalHStack: Layout {
    let weights: [CGFloat]
    var spacing: CGFloat = Theme.Spacing.md

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = columnWidths(total: proposal.width ?? idealWidth(subviews), count: subviews.count)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height }
            .max() ?? 0
        return CGSize(width: widths.reduce(0, +) + gaps(subviews.count), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, columnWidths(total: bounds.width, count: subviews.count)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func columnWidths(total: CGFloat, count: Int) -> [CGFloat] {
        let weights = (0..<count).map { $0 < self.weights.count ? self.weights[$0] : 1 }
        let sum = weights.reduce(0, +)
        let available = max(total - gaps(count), 0)
        return weights.map { sum > 0 ? available * $0 / sum : 0 }
    }

    /// Наименьшая ширина, при которой каждая колонка не уже своего содержимого
    /// (по ней `ViewThatFits` решает, помещается ли ряд).
    private func idealWidth(_ subviews: Subviews) -> CGFloat {
        let weights = (0..<subviews.count).map { $0 < self.weights.count ? self.weights[$0] : 1 }
        let sum = weights.reduce(0, +)
        let perWeight = zip(subviews, weights)
            .map { $1 > 0 ? $0.sizeThatFits(.unspecified).width / $1 : 0 }
            .max() ?? 0
        return perWeight * sum + gaps(subviews.count)
    }

    private func gaps(_ count: Int) -> CGFloat {
        spacing * CGFloat(max(count - 1, 0))
    }
}

/// Содержимое прокрутки не ниже `minHeight`: пока помещается — получает ровно эту высоту (Spacer'ы раздвигаются,
/// как без прокрутки), не помещается — свою и прокручивается. `frame(minHeight:)` так не умеет: в `ScrollView`
/// высота не предлагается, и рамка только центрирует содержимое.
struct FillHeightLayout: Layout {
    let minHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let natural = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        guard natural.height < minHeight else { return natural }
        return subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: minHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Перенос по строкам: имя категории и чипы подкатегорий во «Всех категориях» (макет `07-picker`).
/// Длинный элемент сужается до ширины строки (текст в нём обрезается многоточием).
struct FlowLayout: Layout {
    var spacing: CGFloat = Theme.Spacing.sm
    var lineSpacing: CGFloat = Theme.Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + line.height / 2),
                    anchor: .leading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            let widthWithItem = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if !line.items.isEmpty, widthWithItem > maxWidth {
                lines.append(line)
                line = Line()
            }
            line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.items.append((index, size))
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
