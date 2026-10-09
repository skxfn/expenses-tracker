/// Пробелы в выводе форматтеров (design/copy.json → voice: неразрывный пробел — U+00A0).
public enum TextSpacing {
    /// U+00A0: число + Br, число + слово, внутри даты, после «≈», в разрядах, перед «—» и «–».
    public static let nonBreaking = "\u{00A0}"

    /// Единственное место нормализации: ICU для `ru` даёт U+00A0 в разрядах и перед символом валюты,
    /// но в датах и других локалях встречаются узкий U+202F, тонкий U+2009 и цифровой U+2007 —
    /// они приводятся к U+00A0. Обычные пробелы не трогаются.
    public static func normalized(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            result.append(otherSpaces.contains(scalar) ? "\u{00A0}" : scalar)
        }
        return String(result)
    }

    private static let otherSpaces: Set<Unicode.Scalar> = ["\u{202F}", "\u{2009}", "\u{2007}"]
}
