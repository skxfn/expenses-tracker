import CoreGraphics
import Foundation

/// Squarified treemap (Bruls, Huizing, van Wijk, 2000) для «Плиток».
public enum Treemap {
    /// Прямоугольники с площадью, пропорциональной `values`, в порядке `values`.
    /// Значения раскладываются в данном порядке (для квадратных плиток — по убыванию).
    /// Ноль и отрицательные значения получают пустой прямоугольник в начале `rect`.
    public static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect(origin: rect.origin, size: .zero), count: values.count)
        let indices = values.indices.filter { values[$0] > 0 && values[$0].isFinite }
        let total = indices.reduce(0) { $0 + values[$1] }
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { max($0, 0) * scale }
        var remaining = rect
        var start = 0
        while start < indices.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var worst = worstRatio(indices[start..<end].map { areas[$0] }, side: side)
            while end < indices.count {
                let candidate = worstRatio(indices[start...end].map { areas[$0] }, side: side)
                guard candidate <= worst else { break }
                worst = candidate
                end += 1
            }
            let row = Array(indices[start..<end])
            let isLast = end == indices.count
            remaining = layout(row, areas: areas, in: remaining, isLast: isLast, into: &result)
            start = end
        }
        return result
    }

    /// Худшее соотношение сторон в ряду вдоль стороны `side`.
    private static func worstRatio(_ row: [Double], side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard sum > 0, side > 0 else { return .infinity }
        let sideSquared = side * side
        let sumSquared = sum * sum
        return row.reduce(0) { worst, area in
            max(worst, max(sideSquared * area / sumSquared, sumSquared / (sideSquared * area)))
        }
    }

    /// Кладёт ряд вдоль короткой стороны `rect` и возвращает остаток.
    private static func layout(
        _ row: [Int], areas: [Double], in rect: CGRect, isLast: Bool, into result: inout [CGRect]
    ) -> CGRect {
        let rowArea = row.reduce(0) { $0 + areas[$1] }
        if rect.width >= rect.height {
            // Колонка слева во всю высоту.
            let width = isLast ? rect.width : CGFloat(rowArea / Double(rect.height))
            var y = rect.minY
            for (offset, index) in row.enumerated() {
                let height = offset == row.count - 1
                    ? rect.maxY - y
                    : CGFloat(areas[index] / rowArea) * rect.height
                result[index] = CGRect(x: rect.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
        } else {
            // Строка сверху во всю ширину.
            let height = isLast ? rect.height : CGFloat(rowArea / Double(rect.width))
            var x = rect.minX
            for (offset, index) in row.enumerated() {
                let width = offset == row.count - 1
                    ? rect.maxX - x
                    : CGFloat(areas[index] / rowArea) * rect.width
                result[index] = CGRect(x: x, y: rect.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        }
    }
}

/// Дуга кольца в радианах: 0 — направо, рост угла — по часовой стрелке на экране (ось y вниз).
public struct RingArc: Sendable, Hashable {
    public let start: Double
    public let end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var span: Double { end - start }
    public var mid: Double { (start + end) / 2 }
}

/// Раскладка сегментов «Кольца» и «Солнца».
public enum RingLayout {
    /// Верх круга — отсюда идут сегменты.
    public static let top = -Double.pi / 2

    /// Дуги по значениям по часовой стрелке от `start`; между соседними частями — зазор `gap` (рад),
    /// зазор есть и на стыке последней с первой. Одна часть — полный круг без зазора.
    /// Нулевые значения получают дугу нулевой длины.
    public static func arcs(_ values: [Double], gap: Double, start: Double = top) -> [RingArc] {
        let positive = values.filter { $0 > 0 && $0.isFinite }.count
        guard positive > 1 else {
            return values.map { $0 > 0 && $0.isFinite
                ? RingArc(start: start, end: start + 2 * .pi)
                : RingArc(start: start, end: start)
            }
        }
        return distribute(values, in: RingArc(start: start, end: start + 2 * .pi), gap: gap, closed: true)
    }

    /// Деление дуги `arc` на части по значениям с зазором `gap` между соседними частями;
    /// края частей совпадают с краями `arc` (внешнее кольцо «Солнца» над сегментом категории).
    public static func subdivide(_ arc: RingArc, values: [Double], gap: Double) -> [RingArc] {
        distribute(values, in: arc, gap: gap, closed: false)
    }

    private static func distribute(_ values: [Double], in arc: RingArc, gap: Double, closed: Bool) -> [RingArc] {
        let isPositive: (Double) -> Bool = { $0 > 0 && $0.isFinite }
        let positive = values.filter(isPositive).count
        let total = values.filter(isPositive).reduce(0, +)
        guard total > 0 else { return values.map { _ in RingArc(start: arc.start, end: arc.start) } }

        let gapCount = closed ? positive : max(positive - 1, 0)
        let gapTotal = min(gap * Double(gapCount), arc.span / 2)
        let gapEach = gapCount == 0 ? 0 : gapTotal / Double(gapCount)
        let available = arc.span - gapTotal
        var cursor = arc.start + (closed ? gapEach / 2 : 0)
        return values.map { value in
            guard isPositive(value) else { return RingArc(start: cursor, end: cursor) }
            let span = available * value / total
            let result = RingArc(start: cursor, end: cursor + span)
            cursor += span + gapEach
            return result
        }
    }
}

/// Подписи-диски вокруг круга: разнести соседей, чтобы не налезали.
public enum RadialLabelLayout {
    /// Углы подписей, где соседние центры (по кругу) не ближе `minSeparation` (рад), порядок сохраняется.
    /// Если по кругу места не хватает, подписи расставляются равномерно.
    public static func spread(_ angles: [Double], minSeparation: Double, iterations: Int = 64) -> [Double] {
        let count = angles.count
        guard count > 1, minSeparation > 0 else { return angles }
        let fullTurn = 2 * Double.pi
        guard minSeparation * Double(count) < fullTurn else {
            let step = fullTurn / Double(count)
            return angles.indices.map { angles[0] + step * Double($0) }
        }
        var result = angles
        for _ in 0..<iterations {
            var moved = false
            for index in 0..<count {
                let next = (index + 1) % count
                var distance = result[next] - result[index]
                if next == 0 { distance += fullTurn }
                let deficit = minSeparation - distance
                guard deficit > 1e-9 else { continue }
                result[index] -= deficit / 2
                result[next] += deficit / 2
                moved = true
            }
            if !moved { break }
        }
        return result
    }
}
