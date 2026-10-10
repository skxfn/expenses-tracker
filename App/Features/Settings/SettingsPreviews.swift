import SwiftUI
import ExpenseCore

// MARK: - Мини-веер

/// Мини-веер образцов в строке «Категории» (макет `12-settings`): до 5 тонов веером от оси-заклёпки.
/// Декоративный: число и озвучку даёт строка.
struct CategoryFan: View {
    let tones: [GouacheTone]

    /// Сколько образцов в веере.
    static let maxCount = 5
    private static let chip = CGSize(width: 8, height: 28)
    /// Окошко подписи у верхнего края образца.
    private static let windowInset: CGFloat = 1.5
    /// Угол крайних образцов от вертикали.
    private static let spread = Angle.degrees(40)
    private static let pivotRadius: CGFloat = 3.5

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    /// Тоны первых `maxCount` категорий в порядке записи, веером по оттенку.
    static func tones(of categories: [ExpenseCategory]) -> [GouacheTone] {
        var tones: [GouacheTone] = []
        for tone in categories.compactMap({ GouacheTone(mainHex: $0.colorHex) }) where !tones.contains(tone) {
            tones.append(tone)
            if tones.count == maxCount { break }
        }
        return tones.sorted { $0.hueRank < $1.hueRank }
    }

    var body: some View {
        Canvas { context, size in
            let pivot = CGPoint(x: size.width / 2, y: size.height - Self.pivotRadius * scale)
            let chip = CGSize(width: Self.chip.width * scale, height: Self.chip.height * scale)
            let inset = Self.windowInset * scale
            for (index, tone) in tones.enumerated() {
                var layer = context
                layer.translateBy(x: pivot.x, y: pivot.y)
                layer.rotate(by: angle(index))
                let body = CGRect(x: -chip.width / 2, y: -chip.height, width: chip.width, height: chip.height)
                layer.fill(Path(roundedRect: body, cornerRadius: 2 * scale), with: .color(tone.main))
                let window = CGRect(x: body.minX + inset, y: body.minY + inset, width: chip.width - inset * 2, height: chip.width - inset * 2)
                layer.fill(Path(roundedRect: window, cornerRadius: scale), with: .color(Theme.paper))
            }
            let radius = Self.pivotRadius * scale
            context.fill(Path(ellipseIn: CGRect(x: pivot.x - radius, y: pivot.y - radius, width: radius * 2, height: radius * 2)), with: .color(Theme.paper))
            let core = radius * 0.55
            context.fill(Path(ellipseIn: CGRect(x: pivot.x - core, y: pivot.y - core, width: core * 2, height: core * 2)), with: .color(Theme.graphite))
        }
        .frame(width: 52 * scale, height: 36 * scale)
        .accessibilityHidden(true)
    }

    private func angle(_ index: Int) -> Angle {
        guard tones.count > 1 else { return .zero }
        let step = Self.spread.degrees * 2 / Double(tones.count - 1)
        return .degrees(-Self.spread.degrees + step * Double(index))
    }
}

// MARK: - Выбор диаграммы на вкладке «Траты»

/// Два превью «Плитки / Кольцо» с радиокнопками (`settings.overview.*`). Рисунки статичные — это иллюстрация
/// вида, а не данные. Выбранный вариант озвучивает система (трейт `.isSelected`).
struct OverviewStylePicker: View {
    @Binding var selection: HomeOverviewStyle

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl * 2) {
            option(.tiles, title: "settings.overview.map") { MiniTilesPreview() }
            option(.ring, title: "settings.overview.ring") { MiniRingPreview() }
        }
        .padding(.horizontal, Theme.Spacing.xl + Theme.Spacing.xs)
        .padding(.vertical, Theme.Spacing.lg)
        .sensoryFeedback(Haptic.selection, trigger: selection)
    }

    private func option(_ style: HomeOverviewStyle, title: LocalizedStringKey, @ViewBuilder preview: () -> some View) -> some View {
        let isSelected = selection == style
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
        return Button {
            selection = style
        } label: {
            VStack(spacing: Theme.Spacing.md) {
                preview()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(Self.previewAspect, contentMode: .fit)
                    .background(Theme.canvas, in: shape)
                    .overlay { shape.strokeBorder(Theme.separator, lineWidth: Theme.Size.hairline) }
                Text(title)
                    .typeStyle(.body)
                    .foregroundStyle(Theme.ink)
                RadioMark(isSelected: isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Карточка превью 132×93 (макет `12-settings`).
    private static let previewAspect: CGFloat = 132 / 93
}

/// Радиокнопка: выбранная — графитовый круг с галочкой, невыбранная — контур graphic.
private struct RadioMark: View {
    let isSelected: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(Theme.ink)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Theme.onInk)
            } else {
                Circle().strokeBorder(Theme.graphic, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Мини-«Плитки»: полоска заголовка и treemap основными тонами (по макету `12-settings`).
private struct MiniTilesPreview: View {
    private let gap: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 132
            VStack(alignment: .leading, spacing: 6 * unit) {
                Capsule()
                    .fill(Theme.ink)
                    .frame(width: 33 * unit, height: 4 * unit)
                HStack(spacing: gap) {
                    tile(.shalfey).frame(width: 36 * unit)
                    VStack(spacing: gap) {
                        tile(.abrikos)
                        tile(.kobalt).frame(height: 18 * unit)
                    }
                    .frame(width: 30 * unit)
                    VStack(spacing: gap) {
                        tile(.ametist).frame(height: 18 * unit)
                        HStack(spacing: gap) {
                            tile(.ultramarin)
                            tile(.grafit)
                        }
                        HStack(spacing: gap) {
                            tile(.tseruleum)
                            tile(.kinovar)
                        }
                        .frame(height: 18 * unit)
                    }
                }
            }
            .padding(.horizontal, 11.5 * unit)
            .padding(.top, 10 * unit)
            .padding(.bottom, 9 * unit)
        }
        .accessibilityHidden(true)
    }

    private func tile(_ tone: GouacheTone) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(tone.main)
    }
}

/// Мини-«Кольцо»: сегменты по оттенку с зазорами и полоска итога в центре (по макету `12-settings`).
private struct MiniRingPreview: View {
    /// Доли сегментов по часовой стрелке от верха.
    private static let segments: [(tone: GouacheTone, share: Double)] = [
        (.kinovar, 0.04), (.abrikos, 0.22), (.shalfey, 0.35), (.tseruleum, 0.06),
        (.kobalt, 0.09), (.ultramarin, 0.07), (.ametist, 0.11), (.grafit, 0.06)
    ]
    private static let gapDegrees = 4.0

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 132
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lineWidth = 9 * unit
            let radius = 37 * unit - lineWidth / 2
            var start = -90.0 + Self.gapDegrees
            for segment in Self.segments {
                let sweep = segment.share * 360
                var arc = Path()
                arc.addArc(center: center, radius: radius,
                           startAngle: .degrees(start + Self.gapDegrees / 2),
                           endAngle: .degrees(start + sweep - Self.gapDegrees / 2),
                           clockwise: false)
                context.stroke(arc, with: .color(segment.tone.main), lineWidth: lineWidth)
                start += sweep
            }
            let bar = CGRect(x: center.x - 11 * unit, y: center.y - 2.25 * unit, width: 22 * unit, height: 4.5 * unit)
            context.fill(Path(roundedRect: bar, cornerRadius: 2.25 * unit), with: .color(Theme.ink))
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Веер и превью") {
    @Previewable @State var style = HomeOverviewStyle.tiles
    ThemePreview {
        VStack(spacing: Theme.Spacing.lg) {
            CategoryFan(tones: [.abrikos, .shalfey, .kobalt, .ultramarin, .ametist])
            SettingsGroup(header: "settings.overview.heading") {
                OverviewStylePicker(selection: $style)
            }
        }
    }
}
#endif
