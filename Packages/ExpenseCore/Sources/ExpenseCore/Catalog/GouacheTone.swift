/// Тон палитры «Гуашь» (DESIGN.md, `.impeccable/design.json` → `colorMeta`).
/// Порядок случаев — порядок по оттенку: для кругов и выбора цвета.
/// В данных хранится `mainHex` (основной светлый тон); роли tint/deep/darktint — в App.
public enum GouacheTone: String, CaseIterable, Sendable, Hashable {
    case krapplak, kinovar, abrikos, okhra, olivka, shalfey, viridon,
         tseruleum, kobalt, ultramarin, ametist, pion, umbra, slanets, grafit

    /// Основной тон в светлой теме, `#RRGGBB`.
    public var mainHex: String {
        switch self {
        case .krapplak: "#CE6C8D"
        case .kinovar: "#D16E5A"
        case .abrikos: "#BE7C30"
        case .okhra: "#967729"
        case .olivka: "#759242"
        case .shalfey: "#3E9B6B"
        case .viridon: "#308F8E"
        case .tseruleum: "#277594"
        case .kobalt: "#4569B4"
        case .ultramarin: "#7585D9"
        case .ametist: "#A978C1"
        case .pion: "#9A4C7C"
        case .umbra: "#886248"
        case .slanets: "#798DA3"
        case .grafit: "#797875"
        }
    }

    /// Индекс в порядке по оттенку (0…14).
    public var hueRank: Int { Self.allCases.firstIndex(of: self)! }

    /// Тон по основному hex (без учёта регистра); `nil` — цвет не из «Гуаши».
    public init?(mainHex hex: String) {
        let normalized = hex.uppercased()
        guard let tone = Self.allCases.first(where: { $0.mainHex == normalized }) else { return nil }
        self = tone
    }
}
