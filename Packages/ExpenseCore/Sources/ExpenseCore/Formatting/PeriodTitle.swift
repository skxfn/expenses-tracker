/// Заголовок периода в шапке: основные и вторичные части («5–7» + «окт», «Октябрь» + «2025»).
/// Разделители (U+00A0, « – ») уже внутри частей, поэтому `text` — просто их склейка.
public struct PeriodTitle: Sendable, Hashable {
    public enum Style: Sendable, Hashable {
        /// Слово или число: «Октябрь», «Сегодня», «2026» — Month Title (вторичная часть — год).
        case word
        /// Даты: «5–7 окт», «28 сен – 4 окт» — Range Days + Range Month.
        case dates
    }

    public struct Part: Sendable, Hashable {
        public let text: String
        /// Вторичная часть — мельче и серым: месяц у дат, год у месяца.
        public let isSecondary: Bool

        public init(_ text: String, isSecondary: Bool = false) {
            self.text = text
            self.isSecondary = isSecondary
        }
    }

    public let style: Style
    public let parts: [Part]

    /// Строка целиком: «5–7 окт», «Октябрь 2025».
    public var text: String { parts.map(\.text).joined() }

    public init(style: Style, parts: [Part]) {
        self.style = style
        self.parts = parts
    }
}
