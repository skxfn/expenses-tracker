import SwiftUI

// MARK: - Бумажный лист

/// Бумажный лист ленты и календаря (DESIGN.md → Layout): paper-surface, верх r 28, тень вверх
/// (`0 -6 24`, в тёмной — чёрная .3 и светлая линия 0,5 по верхнему краю). Сплошной, не стекло.
struct PaperSheetBackground: View {
    static let shape = UnevenRoundedRectangle(
        topLeadingRadius: Theme.Radius.sheetPanel,
        topTrailingRadius: Theme.Radius.sheetPanel,
        style: .continuous
    )

    var body: some View {
        Self.shape
            .fill(Theme.surface)
            .paperShadow(Tokens.Shadow.sheet)
            .overlay {
                Self.shape
                    .stroke(Theme.sheetHighlight, lineWidth: 1)
                    .mask(alignment: .top) {
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: Theme.Radius.sheetPanel)
                    }
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Фон-лист под содержимым; нижний край уходит под таб-бар и за край экрана.
    func paperSheetBackground() -> some View {
        background {
            PaperSheetBackground()
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Группа настроек

/// Группа настроек (DESIGN.md → Cards / Containers): paper-surface r 22, контур 0,5, разделители 0,5
/// separator с отступом 16 между строками. Заголовок — SF 15/600 secondary, сноска — SF 13 secondary.
struct SettingsGroup<Content: View>: View {
    var header: LocalizedStringKey?
    var footer: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(header: LocalizedStringKey? = nil, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let header {
                Text(header)
                    .typeStyle(.callout)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews) { subview in
                        subview
                        if subview.id != subviews.last?.id {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: Theme.Size.hairline)
                                .padding(.leading, Theme.Spacing.lg)
                        }
                    }
                }
            }
            .background(Theme.surface, in: shape)
            .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
            if let footer {
                Text(footer)
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }
}

/// Строка группы настроек: подпись слева, значение secondary и шеврон graphic справа, высота от 52.
/// На AX-размерах строка, которая не помещается в ряд, идёт столбиком: значение (с аксессуаром) под подписью —
/// иначе подпись рвётся по слогам, а значение обрезается.
struct SettingsRow<Accessory: View>: View {
    let title: LocalizedStringKey
    var value: String?
    var showsChevron = false
    @ViewBuilder var accessory: Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    inline
                    stacked
                }
            } else {
                inline
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(minHeight: Theme.Size.field)
        .contentShape(Rectangle())
    }

    private var inline: some View {
        HStack(spacing: Theme.Spacing.md) {
            titleText
            Spacer(minLength: Theme.Spacing.sm)
            accessory
            valueText
                .lineLimit(1)
            chevron
        }
    }

    private var stacked: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                titleText
                if value != nil || Accessory.self != EmptyView.self {
                    HStack(spacing: Theme.Spacing.md) {
                        accessory
                        valueText
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
            Spacer(minLength: 0)
            chevron
        }
    }

    private var titleText: some View {
        Text(title)
            .typeStyle(.body)
            .foregroundStyle(Theme.ink)
    }

    @ViewBuilder
    private var valueText: some View {
        if let value {
            Text(value)
                .typeStyle(.body)
                .foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder
    private var chevron: some View {
        if showsChevron {
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.graphic)
                .accessibilityHidden(true)
        }
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(_ title: LocalizedStringKey, value: String? = nil, showsChevron: Bool = false) {
        self.init(title: title, value: value, showsChevron: showsChevron) { EmptyView() }
    }
}

#if DEBUG
#Preview("Лист и группа") {
    ThemePreview {
        VStack(spacing: Theme.Spacing.xl) {
            SettingsGroup(footer: "Последняя копия: 1 окт") {
                SettingsRow("Валюта", value: "Белорусский рубль · \u{20C5}", showsChevron: true)
                SettingsRow("Категории", value: "12", showsChevron: true)
            }
            SettingsGroup(header: "О приложении") {
                SettingsRow("Версия", value: "1.0.0")
            }
            Color.clear
                .frame(height: 120)
                .paperSheetBackground()
        }
    }
}
#endif
