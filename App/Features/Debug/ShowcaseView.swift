#if DEBUG
import SwiftUI
import UIKit
import CoreText
import ExpenseCore

// Витрина фундамента дизайна «Образцы»: токены, «Гуашь», компоненты, стекло, шрифт.
// Каждая страница рисуется в текущей теме системы — скриншоты снимаются в светлой и тёмной.

// MARK: - Общее

private struct ShowcaseSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(verbatim: title)
                .typeStyle(.footnoteStrong)
                .foregroundStyle(Theme.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShowcasePageLayout<Content: View>: View {
    let title: String
    var aura: [GouacheTone] = []
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                content
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background { AuraBackground(tones: aura).ignoresSafeArea() }
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func hex(_ value: UInt32) -> String {
    String(format: "%06X", value)
}

// MARK: - Токены

struct TokensShowcase: View {
    private let neutrals: [(String, TokenPair)] = [
        ("canvas", Tokens.Neutral.canvas), ("canvasElevated", Tokens.Neutral.canvasElevated),
        ("surface", Tokens.Neutral.surface), ("ink", Tokens.Neutral.ink),
        ("secondary", Tokens.Neutral.secondary), ("tertiary", Tokens.Neutral.tertiary),
        ("placeholder", Tokens.Neutral.placeholder), ("graphic", Tokens.Neutral.graphic),
        ("separator", Tokens.Neutral.separator), ("destructive", Tokens.Neutral.destructive),
        ("onInk", Tokens.Neutral.onInk), ("sheetBehind", Tokens.Neutral.sheetBehind),
    ]

    var body: some View {
        ShowcasePageLayout(title: "Токены") {
            ShowcaseSection(title: "Нейтрали (свет / ночь)") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(neutrals, id: \.0) { name, pair in
                        VStack(alignment: .leading, spacing: 2) {
                            RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
                                .fill(Color(pair))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
                                        .strokeBorder(Theme.separator, lineWidth: Theme.Size.hairline)
                                }
                                .frame(height: 34)
                            Text(verbatim: name).typeStyle(.caption).foregroundStyle(Theme.ink)
                            Text(verbatim: "\(hex(pair.light)) · \(hex(pair.dark))")
                                .font(.system(size: 9).monospaced())
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }

            ShowcaseSection(title: "heat-0…4, цифры по шкале") {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(0..<Theme.heatLevels, id: \.self) { level in
                        VStack(alignment: .leading) {
                            Text(verbatim: "\(level + 4)").typeStyle(.footnoteStrong)
                            Text(verbatim: "64").typeStyle(.footnote).monospacedDigit()
                        }
                        .foregroundStyle(Theme.heatDigits(level))
                        .padding(6)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.calendarCell, alignment: .topLeading)
                        .background(Theme.heat(level), in: .rect(cornerRadius: Theme.Radius.swatch, style: .continuous))
                    }
                }
            }

            ShowcaseSection(title: "Шрифты (Unbounded — суммы и месяц, SF — остальное)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Октябрь").typeStyle(.monthTitle)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: "5–7").typeStyle(.rangeDays)
                        Text(verbatim: "окт").typeStyle(.rangeMonth).foregroundStyle(Theme.secondary)
                    }
                    Text(verbatim: "Настройки").typeStyle(.largeTitle)
                    Text(verbatim: "Title 22/600").typeStyle(.title)
                    Text(verbatim: "Headline 17/600").typeStyle(.headline)
                    Text(verbatim: "Body 17/400").typeStyle(.body)
                    Text(verbatim: "Callout 15/600 — сегменты, заголовки дней").typeStyle(.callout)
                    Text(verbatim: "Footnote 13 — категория под заметкой").typeStyle(.footnote)
                    Text(verbatim: "Caption 11/600 — подписи таб-бара").typeStyle(.caption)
                }
                .foregroundStyle(Theme.ink)
            }

            ShowcaseSection(title: "Радиусы: 2 · 6 · 7 · 10 · 12 · 14 · 22 · 28") {
                HStack(spacing: 6) {
                    ForEach([Theme.Radius.chipInner, Theme.Radius.swatch, Theme.Radius.tile, Theme.Radius.plaque,
                             Theme.Radius.lens, Theme.Radius.field, Theme.Radius.group, Theme.Radius.sheetPanel], id: \.self) { radius in
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Theme.surface)
                            .overlay {
                                RoundedRectangle(cornerRadius: radius, style: .continuous)
                                    .strokeBorder(Theme.graphic, lineWidth: 1)
                            }
                            .frame(width: 38, height: 38)
                    }
                }
            }
        }
    }
}

// MARK: - «Гуашь»

struct TonesShowcase: View {
    var body: some View {
        ShowcasePageLayout(title: "«Гуашь»") {
            Text(verbatim: "основной · Aa · плашка · ступени 1–5 · штриховка")
                .typeStyle(.footnote)
                .foregroundStyle(Theme.secondary)
            VStack(spacing: 6) {
                ForEach(GouacheTone.allCases, id: \.self) { tone in
                    ToneRow(tone: tone)
                }
                ToneRow(tone: nil)
            }
        }
    }
}

private struct ToneRow: View {
    let tone: GouacheTone?

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: tone?.rawValue ?? "без кат.")
                .typeStyle(.footnote)
                .foregroundStyle(Theme.ink)
                .frame(width: 70, alignment: .leading)
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(CategoryPaint.main(tone))
                .overlay {
                    Text(verbatim: "Aa")
                        .typeStyle(.footnoteStrong)
                        .foregroundStyle(tone?.labelOnMain ?? Theme.paper)
                }
                .frame(width: 34, height: 30)
            CategoryPlaque(iconName: tone.map(Self.icon) ?? CategoryPaint.uncategorizedIconName, tone: tone)
                .scaleEffect(30 / 36)
                .frame(width: 30, height: 30)
            if let tone {
                HStack(spacing: Theme.Spacing.segmentGap) {
                    ForEach(0..<SubcategoryShades.stepCount, id: \.self) { step in
                        RoundedRectangle(cornerRadius: Theme.Radius.chipInner, style: .continuous)
                            .fill(tone.shade(step))
                            .overlay {
                                Text(verbatim: "\(step + 1)")
                                    .typeStyle(.caption)
                                    .foregroundStyle(tone.labelOnShade(step))
                            }
                            .frame(width: 24, height: 30)
                    }
                }
                HatchFill(tone: tone)
                    .frame(width: 30, height: 30)
                    .clipShape(.rect(cornerRadius: Theme.Radius.chipInner, style: .continuous))
            } else {
                Spacer()
            }
        }
    }

    private static func icon(for tone: GouacheTone) -> String {
        switch tone {
        case .krapplak: "gift-fill"
        case .kinovar: "capsule-fill"
        case .abrikos: "fork-knife-fill"
        case .okhra: "mortarboard-fill"
        case .olivka: "leaf-fill"
        case .shalfey: "basket-fill"
        case .viridon: "paw-fill"
        case .tseruleum: "wifi-fill"
        case .kobalt: "bus-fill"
        case .ultramarin: "repeat-fill"
        case .ametist: "celebrate-fill"
        case .pion: "t-shirt-fill"
        case .umbra: "home-4-fill"
        case .slanets: "barbell-fill"
        case .grafit: "more-3-fill"
        }
    }
}

// MARK: - Компоненты

struct ComponentsShowcase: View {
    @State private var selectedSwatch = 0
    @State private var total: Int64 = 41_230
    @State private var period = 2

    private let swatches: [(String, GouacheTone?)] = [
        ("shopping-cart-1-fill", .shalfey), ("fork-knife-fill", .abrikos), ("teacup-fill", .abrikos),
        ("car-fill", .kobalt), (CategoryPaint.uncategorizedIconName, nil),
    ]

    var body: some View {
        ShowcasePageLayout(title: "Компоненты", aura: [.shalfey, .abrikos]) {
            GlassSegmentedControl(title: "Период", selection: $period, items: [
                .init(value: 0, title: "День"), .init(value: 1, title: "Неделя"), .init(value: 2, title: "Месяц"),
                .init(value: 3, title: "Год"), .init(value: 4, title: "Свой"),
            ])

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                AmountText(text: Self.format(total), value: Double(total), size: .total, currency: "Br")
                    .onTapGesture { total += 1_111 }
                ShowcaseSection(title: "Табличные цифры: столбец должен быть ровным") {
                    VStack(alignment: .trailing, spacing: 2) {
                        AmountText(text: "111,11", value: 0, size: .inline)
                        AmountText(text: "888,88", value: 0, size: .inline)
                        AmountText(text: "1 204,70", value: 0, size: .inlineStrong)
                    }
                }
                ShowcaseSection(title: "Плашки 36 · 52, «основной тон», «Без категории»") {
                    HStack(spacing: Theme.Spacing.sm) {
                        CategoryPlaque(iconName: "basket-fill", tone: .shalfey)
                        CategoryPlaque(iconName: "fork-knife-fill", tone: .abrikos)
                        CategoryPlaque(iconName: "bus-fill", tone: .kobalt)
                        CategoryPlaque(iconName: "basket-fill", tone: .shalfey, fill: .main)
                        CategoryPlaque(iconName: CategoryPaint.uncategorizedIconName, tone: nil)
                        CategoryPlaque(iconName: "teacup-fill", tone: .abrikos, size: .large)
                    }
                }
                ShowcaseSection(title: "Образцы 46×60 (тап — выбор)") {
                    HStack(spacing: 6) {
                        ForEach(swatches.indices, id: \.self) { index in
                            Button {
                                selectedSwatch = index
                            } label: {
                                CategorySwatch(iconName: swatches[index].0, tone: swatches[index].1, isSelected: index == selectedSwatch)
                            }
                            .buttonStyle(.plain)
                        }
                        AllCategoriesSwatch(title: "Все")
                    }
                    .padding(.top, Theme.Size.swatchLift)
                    .sensoryFeedback(Haptic.selection, trigger: selectedSwatch)
                }
                ShowcaseSection(title: "Штриховка «без подкатегории»") {
                    HStack(spacing: Theme.Spacing.categoryGap) {
                        ForEach([GouacheTone.shalfey, .abrikos, .pion, .grafit], id: \.self) { tone in
                            HatchFill(tone: tone)
                                .frame(height: 18)
                                .clipShape(.rect(cornerRadius: Theme.Radius.chipInner, style: .continuous))
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .paperSheetBackground()

            SettingsGroup(header: "Резервная копия", footer: "Последняя копия: 1 окт") {
                SettingsRow("Валюта", value: "Белорусский рубль · Br", showsChevron: true)
                SettingsRow("Версия", value: "1.0.0")
            }
        }
    }

    private static func format(_ minor: Int64) -> String {
        let rubles = (minor / 100).formatted(.number.grouping(.automatic).locale(Locale(identifier: "ru_RU")))
        return rubles + "," + String(format: "%02lld", minor % 100)
    }
}

// MARK: - Стекло и кнопки

struct GlassShowcase: View {
    @State private var isToastShown = true
    @State private var period = 2
    @Namespace private var glassNamespace

    var body: some View {
        ShowcasePageLayout(title: "Стекло", aura: [.shalfey, .abrikos, .ametist]) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(verbatim: "Октябрь").typeStyle(.monthTitle).foregroundStyle(Theme.ink)
                Spacer()
                GlassEffectContainer {
                    HStack(spacing: Theme.Spacing.sm) {
                        GlassStepperPair(previousLabel: "Назад", nextLabel: "Вперёд", canGoNext: false, onPrevious: {}, onNext: {})
                        Button("Настройки", systemImage: "gearshape") {}
                            .buttonStyle(.glassCircle())
                    }
                }
            }

            ShowcaseSection(title: "Свои стили: glass · prominent · destructive · «+» 62") {
                HStack(spacing: Theme.Spacing.md) {
                    Button("Ещё одна") {}.buttonStyle(.glassCapsule())
                    Button("Сохранить") {}.buttonStyle(.glassCapsule(.prominent))
                }
                HStack(spacing: Theme.Spacing.md) {
                    Button("Удалить", systemImage: "trash") {}.buttonStyle(.glassCapsule(.destructive))
                    Button("Новая трата", systemImage: "plus") {}
                        .buttonStyle(.glassCircle(diameter: Theme.Size.addButton, prominent: true))
                }
            }

            ShowcaseSection(title: "Системные: .glass · .glassProminent (tint ink)") {
                HStack(spacing: Theme.Spacing.md) {
                    Button("Ещё одна") {}
                        .glassButtonStyle()
                        .controlSize(.large)
                    Button("Сохранить") {}
                        .prominentGlassButtonStyle()
                        .controlSize(.large)
                    Button("Закрыть", systemImage: "xmark", role: .close) {}
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                }
            }

            ShowcaseSection(title: "glass-k: быстрые суммы в GlassEffectContainer") {
                GlassEffectContainer(spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach([5, 10, 20, 50, 100], id: \.self) { value in
                            Button {} label: {
                                Text(verbatim: "+\(value)")
                                    .typeStyle(.amountInline)
                                    .foregroundStyle(Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: Theme.Size.chip)
                            }
                            .buttonStyle(.plain)
                            .glass(.key)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ShowcaseSection(title: "glass-in на листе: заголовок дня") {
                    HStack {
                        Text(verbatim: "Сегодня").typeStyle(.callout)
                        Text(verbatim: "· чт, 8 окт").typeStyle(.callout).foregroundStyle(Theme.secondary)
                        Spacer()
                        AmountText(text: "57,20", value: 5_720, size: .inlineStrong)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.Size.dayHeader)
                    .glass(.inContent)
                }
                ShowcaseSection(title: "Линза «сегодня» над клеткой heat (на 2 и на 4)") {
                    HStack(spacing: Theme.Spacing.lg) {
                        ForEach([2, 4], id: \.self) { level in
                            ZStack {
                                RoundedRectangle(cornerRadius: Theme.Radius.swatch, style: .continuous)
                                    .fill(Theme.heat(level))
                                    .frame(width: 48, height: Theme.Size.calendarCell)
                                Text(verbatim: "8")
                                    .typeStyle(.footnoteStrong)
                                    .foregroundStyle(Theme.heatDigits(level))
                                    .frame(width: 60, height: 64)
                                    .glassLens()
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .paperSheetBackground()

            Color.clear.frame(height: 70)
        }
        .glassToast(isPresented: isToastShown, bottomPadding: Theme.Spacing.xl) {
            GlassToast(message: "Удалено", action: .init(title: "Отменить") { isToastShown = false })
        }
    }
}

// MARK: - Unbounded

struct FontsShowcase: View {
    private let report = FontReport.make()

    var body: some View {
        ShowcasePageLayout(title: "Unbounded") {
            ForEach(report.lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.system(size: 13).monospaced())
                    .foregroundStyle(Theme.ink)
            }
            ShowcaseSection(title: "SwiftUI .monospacedDigit(): ширины должны совпасть") {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: "1111,11").typeStyle(.amountTotal)
                    Text(verbatim: "8888,88").typeStyle(.amountTotal)
                }
                .foregroundStyle(Theme.ink)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.destructive).frame(width: 1) }
            }
            ShowcaseSection(title: "Без tnum (пропорциональные)") {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: "1111,11")
                    Text(verbatim: "8888,88")
                }
                .font(TypeStyle.amountTotal.font)
                .foregroundStyle(Theme.ink)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.destructive).frame(width: 1) }
            }
        }
    }
}

/// Проверка регистрации Unbounded и табличных цифр через UIKit/CoreText на устройстве.
private enum FontReport {
    struct Result {
        let lines: [String]
    }

    static func make() -> Result {
        var lines: [String] = []
        let families = UIFont.familyNames.filter { $0.localizedCaseInsensitiveContains("Unbounded") }
        lines.append("Семейства: \(families.joined(separator: ", "))")
        for family in families {
            lines.append("  \(family): \(UIFont.fontNames(forFamilyName: family).joined(separator: ", "))")
        }
        for name in [UnboundedFont.Weight.medium.postScriptName, UnboundedFont.Weight.semibold.postScriptName] {
            guard let font = UIFont(name: name, size: 40) else {
                lines.append("\(name): НЕ НАЙДЕН")
                continue
            }
            let tabular = font.withTabularDigits()
            let plainWidths = widths(of: ["1111", "8888"], font: font)
            let tabularWidths = widths(of: ["1111", "8888"], font: tabular)
            lines.append("\(name): ok")
            lines.append("  без tnum 1111/8888: \(plainWidths)")
            lines.append("  с tnum   1111/8888: \(tabularWidths)")
            lines.append("  tnum в списке фич: \(hasTabularFeature(font) ? "да" : "нет")")
        }
        return Result(lines: lines)
    }

    private static func widths(of strings: [String], font: UIFont) -> String {
        strings
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .map { String(format: "%.1f", $0) }
            .joined(separator: " / ")
    }

    private static func hasTabularFeature(_ font: UIFont) -> Bool {
        guard let features = CTFontCopyFeatures(font as CTFont) as? [[String: Any]] else { return false }
        return features.contains { feature in
            (feature[kCTFontFeatureTypeIdentifierKey as String] as? Int) == kNumberSpacingType
                && ((feature[kCTFontFeatureTypeSelectorsKey as String] as? [[String: Any]]) ?? []).contains {
                    ($0[kCTFontFeatureSelectorIdentifierKey as String] as? Int) == kMonospacedNumbersSelector
                }
        }
    }
}

private extension UIFont {
    func withTabularDigits() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
