import SwiftUI
import CoreText
import OSLog

/// Шрифтовой стиль: шрифт с Dynamic Type, трекинг и табличные цифры (DESIGN.md → Typography, §3.3).
/// Unbounded — только суммы, «Br» и месяц; остальное — системный SF.
nonisolated struct TypeStyle: Sendable {
    let font: Font
    /// Кегль при размере текста по умолчанию.
    let size: CGFloat
    /// С каким системным стилем масштабируется (Dynamic Type).
    let textStyle: Font.TextStyle
    let trackingEm: CGFloat
    let tabularDigits: Bool
}

nonisolated extension TypeStyle {
    // MARK: Unbounded

    /// Сумма в шите записи, 60/500.
    static let amountDisplay = unbounded(Tokens.TypeScale.amountDisplay, relativeTo: .largeTitle)
    /// «Br» рядом с amount-display, 26/500.
    static let currencyDisplay = unbounded(size: 26, weight: .medium, relativeTo: .largeTitle)
    /// Итог периода, 40/500.
    static let amountTotal = unbounded(Tokens.TypeScale.amountTotal, relativeTo: .largeTitle)
    /// «Br» рядом с amount-total, 20/500.
    static let currencyTotal = unbounded(size: 20, weight: .medium, relativeTo: .largeTitle)
    /// Итог в центре кольца, 28/500.
    static let amountRingTotal = unbounded(size: 28, weight: .medium, relativeTo: .title, base: Tokens.TypeScale.amountTotal)
    /// «Br» в центре кольца: в токенах нет, по макету `02-home-ring` ≈ половина кегля итога.
    static let currencyRingTotal = unbounded(size: 14, weight: .medium, relativeTo: .title)
    /// Месяц в шапке, 28/600.
    static let monthTitle = unbounded(Tokens.TypeScale.monthTitle, relativeTo: .title)
    /// Год рядом с месяцем, Unbounded 500 20 (secondary).
    static let monthYear = unbounded(size: 20, weight: .medium, relativeTo: .title)
    /// Дни своего периода «5–7», 22/600.
    static let rangeDays = unbounded(Tokens.TypeScale.rangeDays, relativeTo: .title2)
    /// Месяц своего периода «окт», 17/500 (secondary).
    static let rangeMonth = unbounded(Tokens.TypeScale.rangeMonth, relativeTo: .body)
    /// Суммы в строках, быстрые суммы, плитки, 15/500.
    static let amountInline = unbounded(Tokens.TypeScale.amountInline, relativeTo: .subheadline)
    /// Сумма в заголовке дня, 15/600.
    static let amountInlineStrong = unbounded(size: 15, weight: .semibold, relativeTo: .subheadline, base: Tokens.TypeScale.amountInline)

    // MARK: SF (системные стили с нужным начертанием: кегли совпадают с DESIGN.md при размере по умолчанию)

    static let largeTitle = system(Tokens.TypeScale.largeTitle, .largeTitle)
    static let title = system(Tokens.TypeScale.title, .title2)
    static let headline = system(Tokens.TypeScale.headline, .headline)
    static let body = system(Tokens.TypeScale.body, .body)
    /// 15/600. Системный `.callout` — 16 pt, поэтому стиль строится от `.subheadline`.
    static let callout = system(Tokens.TypeScale.callout, .subheadline)
    /// 15/400 — фраза-сравнение, пустые состояния.
    static let subheadline = system(Tokens.TypeScale.callout, .subheadline, weight: .regular)
    static let footnote = system(Tokens.TypeScale.footnote, .footnote)
    /// 13/600 — доли, подписи визуализаций, подзаголовки групп иконок.
    static let footnoteStrong = system(Tokens.TypeScale.footnote, .footnote, weight: .semibold)
    /// 11/600 — подписи таб-бара и шкалы календаря. Мельче не бывает.
    static let caption = system(Tokens.TypeScale.caption, .caption2)

    // MARK: Построение

    private static func unbounded(_ token: TypeScaleToken, relativeTo style: Font.TextStyle) -> TypeStyle {
        unbounded(size: token.size, weight: UnboundedFont.Weight(token.weight), relativeTo: style, base: token)
    }

    private static func unbounded(
        size: CGFloat,
        weight: UnboundedFont.Weight,
        relativeTo style: Font.TextStyle,
        base: TypeScaleToken? = nil
    ) -> TypeStyle {
        TypeStyle(
            font: .custom(weight.postScriptName, size: size, relativeTo: style),
            size: size,
            textStyle: style,
            trackingEm: base?.trackingEm ?? 0,
            tabularDigits: true
        )
    }

    private static func system(_ token: TypeScaleToken, _ style: Font.TextStyle, weight: Font.Weight? = nil) -> TypeStyle {
        TypeStyle(
            font: .system(style).weight(weight ?? Font.Weight(token.weight)),
            size: token.size,
            textStyle: style,
            trackingEm: token.trackingEm,
            tabularDigits: token.tabularDigits
        )
    }
}

extension Font.Weight {
    nonisolated init(_ cssWeight: Int) {
        switch cssWeight {
        case ..<350: self = .light
        case ..<450: self = .regular
        case ..<550: self = .medium
        case ..<650: self = .semibold
        case ..<750: self = .bold
        default: self = .heavy
        }
    }
}

extension View {
    /// Шрифт, трекинг (масштабируется вместе с Dynamic Type) и табличные цифры стиля.
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }
}

private struct TypeStyleModifier: ViewModifier {
    let style: TypeStyle
    @ScaledMetric private var tracking: CGFloat

    init(style: TypeStyle) {
        self.style = style
        _tracking = ScaledMetric(wrappedValue: style.trackingEm * style.size, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        let styled = content.font(style.font).tracking(tracking)
        if style.tabularDigits {
            styled.monospacedDigit()
        } else {
            styled
        }
    }
}

// MARK: - Unbounded

/// Встроенный Unbounded (OFL, `App/Resources/Fonts`). Регистрируется при запуске на время процесса,
/// Info.plist и версия приложения не затрагиваются (§3.3, вариант б).
nonisolated enum UnboundedFont {
    enum Weight: Sendable {
        case medium, semibold

        init(_ cssWeight: Int) {
            self = cssWeight >= 600 ? .semibold : .medium
        }

        /// PostScript-имя (проверено по таблице name: `Unbounded-Medium`, `Unbounded-SemiBold`).
        var postScriptName: String {
            switch self {
            case .medium: "Unbounded-Medium"
            case .semibold: "Unbounded-SemiBold"
            }
        }
    }

    static let fileNames = ["Unbounded-Medium", "Unbounded-SemiBold"]

    private static let logger = Logger(subsystem: "com.skxfn.expenses", category: "Fonts")

    /// Регистрирует TTF из бандла. Без шрифта SwiftUI молча подставит системный — ошибку пишем в лог.
    static func register(bundle: Bundle = .main) {
        for name in fileNames {
            guard let url = bundle.url(forResource: name, withExtension: "ttf") else {
                logger.error("Нет шрифта \(name, privacy: .public).ttf в бандле")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let description = error?.takeRetainedValue().localizedDescription ?? "неизвестная ошибка"
                logger.error("Шрифт \(name, privacy: .public) не зарегистрирован: \(description, privacy: .public)")
            }
        }
    }
}
