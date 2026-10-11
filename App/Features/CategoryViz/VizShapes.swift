import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import ExpenseCore

/// Сегмент кольца со скруглёнными углами. Углы — в радианах, 0 — направо, рост — по часовой стрелке
/// (ось y вниз), как `RingArc`. Начало и конец анимируются: так сегмент разрастается в полный круг
/// при раскрытии категории. Полный круг рисуется кольцом без шва.
struct AnnularSector: Shape {
    var start: Double
    var end: Double
    let inner: CGFloat
    let outer: CGFloat
    var corner: CGFloat = 0

    init(_ arc: RingArc, inner: CGFloat, outer: CGFloat, corner: CGFloat = 0) {
        start = arc.start
        end = arc.end
        self.inner = inner
        self.outer = outer
        self.corner = corner
    }

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set {
            start = newValue.first
            end = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let span = end - start
        guard span > 1e-4, outer > inner else { return Path() }
        if span >= 2 * .pi - 1e-4 {
            return Self.annulus(center: center, inner: inner, outer: outer)
        }
        let radius = clampedCorner(span: span)
        guard radius > 0.01 else {
            return Self.sharpSector(center: center, start: start, span: span, inner: inner, outer: outer)
        }
        return roundedSector(center: center, span: span, radius: radius)
    }

    /// Скругление не больше половины толщины и не больше, чем помещается в угол дуги.
    private func clampedCorner(span: Double) -> CGFloat {
        var radius = min(corner, (outer - inner) / 2)
        let sine = span >= .pi ? 1 : CGFloat(sin(span / 2))
        radius = min(radius, outer * sine / (1 + sine))
        if sine < 1 { radius = min(radius, inner * sine / (1 - sine)) }
        return max(radius, 0)
    }

    private func roundedSector(center: CGPoint, span: Double, radius c: CGFloat) -> Path {
        let point = { (distance: CGFloat, angle: Double) in
            CGPoint(x: center.x + distance * CGFloat(cos(angle)), y: center.y + distance * CGFloat(sin(angle)))
        }
        let outerTilt = asin(Double(c / (outer - c)))
        let innerTilt = asin(Double(c / (inner + c)))
        let outerReach = sqrt((outer - c) * (outer - c) - c * c)
        let innerReach = sqrt((inner + c) * (inner + c) - c * c)
        let quarter = Double.pi / 2

        var path = Path()
        path.move(to: point(innerReach, start))
        path.addLine(to: point(outerReach, start))
        path.addRelativeArc(center: point(outer - c, start + outerTilt), radius: c,
                            startAngle: .radians(start - quarter), delta: .radians(quarter + outerTilt))
        path.addRelativeArc(center: center, radius: outer,
                            startAngle: .radians(start + outerTilt), delta: .radians(span - 2 * outerTilt))
        path.addRelativeArc(center: point(outer - c, end - outerTilt), radius: c,
                            startAngle: .radians(end - outerTilt), delta: .radians(quarter + outerTilt))
        path.addLine(to: point(innerReach, end))
        path.addRelativeArc(center: point(inner + c, end - innerTilt), radius: c,
                            startAngle: .radians(end + quarter), delta: .radians(quarter - innerTilt))
        path.addRelativeArc(center: center, radius: inner,
                            startAngle: .radians(end - innerTilt), delta: .radians(-(span - 2 * innerTilt)))
        path.addRelativeArc(center: point(inner + c, start + innerTilt), radius: c,
                            startAngle: .radians(start + innerTilt + .pi), delta: .radians(quarter - innerTilt))
        path.closeSubpath()
        return path
    }

    private static func sharpSector(
        center: CGPoint, start: Double, span: Double, inner: CGFloat, outer: CGFloat
    ) -> Path {
        var path = Path()
        path.addRelativeArc(center: center, radius: outer, startAngle: .radians(start), delta: .radians(span))
        path.addRelativeArc(center: center, radius: inner, startAngle: .radians(start + span), delta: .radians(-span))
        path.closeSubpath()
        return path
    }

    /// Кольцо: внешняя окружность по часовой, внутренняя — против (правило ненулевой обмотки).
    private static func annulus(center: CGPoint, inner: CGFloat, outer: CGFloat) -> Path {
        var path = Path()
        path.addRelativeArc(center: center, radius: outer, startAngle: .zero, delta: .radians(2 * .pi))
        path.closeSubpath()
        path.move(to: CGPoint(x: center.x + inner, y: center.y))
        path.addRelativeArc(center: center, radius: inner, startAngle: .zero, delta: .radians(-2 * .pi))
        path.closeSubpath()
        return path
    }
}

/// Плитка treemap: радиус 7 у углов, что смотрят наружу, и 2 — у внутренних (подкатегории в плитке
/// категории, DESIGN.md → «Плитки»).
nonisolated struct TileCorners: Sendable, Hashable {
    var topLeading: CGFloat
    var bottomLeading: CGFloat
    var bottomTrailing: CGFloat
    var topTrailing: CGFloat

    static let tile = TileCorners(all: Theme.Radius.tile)

    init(all radius: CGFloat) {
        topLeading = radius
        bottomLeading = radius
        bottomTrailing = radius
        topTrailing = radius
    }

    /// Углы части внутри `container`: совпадающий с углом контейнера — `outer`, остальные — `inner`.
    init(of rect: CGRect, in container: CGRect, outer: CGFloat, inner: CGFloat) {
        let tolerance: CGFloat = 0.5
        let left = abs(rect.minX - container.minX) < tolerance
        let right = abs(rect.maxX - container.maxX) < tolerance
        let top = abs(rect.minY - container.minY) < tolerance
        let bottom = abs(rect.maxY - container.maxY) < tolerance
        topLeading = left && top ? outer : inner
        bottomLeading = left && bottom ? outer : inner
        bottomTrailing = right && bottom ? outer : inner
        topTrailing = right && top ? outer : inner
    }

    var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topLeading,
            bottomLeadingRadius: bottomLeading,
            bottomTrailingRadius: bottomTrailing,
            topTrailingRadius: topTrailing,
            style: .continuous
        )
    }
}

/// Раскладка плиток с зазором: соседние плитки разведены на `gap`, внешние края совпадают с полем.
/// `minSide` — наименьшая сторона плитки (0 — строго по площади).
nonisolated enum TileLayout {
    static func rects(_ values: [Double], in field: CGRect, gap: CGFloat, minSide: CGFloat = 0) -> [CGRect] {
        let half = gap / 2
        let outer = field.insetBy(dx: -half, dy: -half)
        return Treemap.squarify(values, in: outer, minSide: minSide > 0 ? minSide + gap : 0).map { rect in
            guard rect.width > gap, rect.height > gap else { return CGRect(origin: rect.origin, size: .zero) }
            return rect.insetBy(dx: half, dy: half)
        }
    }
}

// MARK: - Зерно и блик кольца

/// Бумажное зерно (fractal noise ≈ 16 %) и блик сверху на сегментах «Кольца» главной
/// (DESIGN.md → «Кольцо»). Зерно — монохромный шум CoreImage, одна плитка на процесс.
struct VizGrainOverlay: View {
    /// Непрозрачность зерна.
    static let grainOpacity: Double = 0.16
    /// Белый блик у верхнего края кольца.
    static let highlightOpacity: Double = 0.22

    var body: some View {
        ZStack {
            if let grain = VizGrain.image {
                Image(decorative: grain, scale: 2)
                    .resizable(resizingMode: .tile)
                    .blendMode(.overlay)
                    .opacity(Self.grainOpacity)
            }
            LinearGradient(
                colors: [Color.white.opacity(Self.highlightOpacity), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .blendMode(.softLight)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum VizGrain {
    /// 128 × 128 pt монохромного шума; `nil`, если CoreImage не отрисовал.
    static let image: CGImage? = {
        let noise = CIFilter.randomGenerator().outputImage
        let mono = CIFilter.colorControls()
        mono.inputImage = noise
        mono.saturation = 0
        mono.contrast = 1.4
        guard let output = mono.outputImage else { return nil }
        return CIContext().createCGImage(output, from: CGRect(x: 0, y: 0, width: 256, height: 256))
    }()
}
