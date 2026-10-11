import CoreGraphics
import Foundation
import Testing
@testable import ExpenseCore

/// Геометрия визуализаций: treemap, дуги колец, разнос подписей.
@Suite struct CategoryVizGeometryTests {
    private let field = CGRect(x: 0, y: 0, width: 358, height: 208)

    private func area(_ rect: CGRect) -> Double { Double(rect.width * rect.height) }

    @Test func treemapAreasAreProportionalAndTileTheField() {
        let values: [Double] = [142.6, 86.4, 44, 38, 31.99, 25, 18.7]
        let rects = Treemap.squarify(values, in: field)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            #expect(abs(area(rect) - area(field) * value / total) < 0.5)
            #expect(field.insetBy(dx: -0.001, dy: -0.001).contains(rect))
        }
        #expect(abs(rects.map(area).reduce(0, +) - area(field)) < 0.5)
        // Без наложений.
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || area(overlap) < 0.01)
            }
        }
    }

    @Test func treemapFirstLargeValueTakesFullHeightColumn() {
        // Как на макете 01-home: «Продукты» 35 % — колонка во всю высоту слева.
        let rects = Treemap.squarify([142.6, 86.4, 44, 38, 31.99, 25, 18.7, 25.61], in: field)
        #expect(rects[0].minX == 0)
        #expect(rects[0].height == 208)
        #expect(rects[0].width > 100 && rects[0].width < 130)
    }

    @Test func treemapHandlesZerosAndEmpty() {
        let rects = Treemap.squarify([0, 10, -3], in: field)
        #expect(rects[0].size == .zero)
        #expect(rects[2].size == .zero)
        #expect(rects[1] == field)
        #expect(Treemap.squarify([], in: field).isEmpty)
        #expect(Treemap.squarify([0], in: field) == [CGRect(origin: .zero, size: .zero)])
    }

    @Test func minSideLeavesOrdinaryLayoutUnchanged() {
        // Как на макете 01-home: самая узкая плитка ≈ 30 — при пороге 28 раскладка та же.
        let values: [Double] = [142.6, 86.4, 44, 38, 31.99, 25.61, 25, 18.7]
        #expect(Treemap.squarify(values, in: field, minSide: 28) == Treemap.squarify(values, in: field))
    }

    @Test(arguments: [[997.0, 3], [9_990, 6, 4], [455_000, 1_200, 900, 500]])
    func minSideKeepsSmallValuesVisible(values: [Double]) {
        // Одна категория на 99 %: без порога остальные — полоски уже пункта.
        let minSide: CGFloat = 31
        let rects = Treemap.squarify(values, in: field, minSide: minSide)
        for rect in rects {
            #expect(min(rect.width, rect.height) >= minSide)
            #expect(field.insetBy(dx: -0.001, dy: -0.001).contains(rect))
        }
        #expect(abs(rects.map(area).reduce(0, +) - area(field)) < 0.5)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].intersection(rects[j])
                #expect(overlap.isNull || area(overlap) < 0.01)
            }
        }
        // Крупная остаётся крупной.
        #expect(area(rects[0]) > area(field) * 0.7)
    }

    @Test func minSideGivesUpWhenFieldIsTooSmall() {
        // 40 значений по 31 pt на поле 358 × 208 не помещаются: раскладка всё равно покрывает поле.
        let values = Array(repeating: 1.0, count: 40) + [1_000]
        let rects = Treemap.squarify(values, in: field, minSide: 31)
        #expect(abs(rects.map(area).reduce(0, +) - area(field)) < 0.5)
        // Порог больше поля — обычная раскладка.
        #expect(Treemap.squarify([5, 1], in: field, minSide: 300) == Treemap.squarify([5, 1], in: field))
    }

    @Test func ringArcsKeepGapsAndOrderFromTop() {
        let gap = 0.02
        let arcs = RingLayout.arcs([3, 1], gap: gap)
        #expect(abs(arcs[0].start - (RingLayout.top + gap / 2)) < 1e-12)
        #expect(abs(arcs[1].start - arcs[0].end - gap) < 1e-12)
        #expect(abs(arcs[0].span / arcs[1].span - 3) < 1e-9)
        // Сумма дуг и зазоров — полный круг.
        #expect(abs(arcs.map(\.span).reduce(0, +) + 2 * gap - 2 * .pi) < 1e-9)
    }

    @Test func singleArcIsFullCircleWithoutGap() {
        let arcs = RingLayout.arcs([0, 5], gap: 0.1)
        #expect(arcs[0].span == 0)
        #expect(abs(arcs[1].span - 2 * .pi) < 1e-12)
        #expect(RingLayout.arcs([], gap: 0.1).isEmpty)
    }

    @Test func subdivideMatchesParentEdges() {
        let parent = RingArc(start: 1, end: 2)
        let parts = RingLayout.subdivide(parent, values: [2, 0, 1], gap: 0.03)
        #expect(parts[0].start == 1)
        #expect(abs(parts[2].end - 2) < 1e-12)
        #expect(parts[1].span == 0)
        #expect(abs(parts[2].start - parts[0].end - 0.03) < 1e-12)
        #expect(abs(parts[0].span / parts[2].span - 2) < 1e-9)
    }

    @Test func labelsSpreadKeepsSeparationAndOrder() {
        let angles = [0.0, 0.05, 0.1, 2.0, 4.0]
        let spread = RadialLabelLayout.spread(angles, minSeparation: 0.3)
        for i in spread.indices {
            let next = (i + 1) % spread.count
            var distance = spread[next] - spread[i]
            if next == 0 { distance += 2 * .pi }
            #expect(distance >= 0.3 - 1e-6)
        }
        // Далёкие от тесноты почти не двигаются.
        #expect(abs(spread[3] - 2.0) < 1e-9)
        #expect(spread == spread.sorted())
    }

    @Test func labelsWithoutRoomAreEven() {
        let spread = RadialLabelLayout.spread([0, 0.1, 0.2, 0.3], minSeparation: 2)
        #expect(abs(spread[1] - spread[0] - .pi / 2) < 1e-12)
    }
}
