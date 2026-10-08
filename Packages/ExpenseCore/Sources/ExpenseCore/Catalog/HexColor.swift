/// Разбор цвета в формате `#RRGGBB`, в котором хранится цвет категории.
public enum HexColor {
    /// Компоненты в диапазоне 0...1 или `nil`, если строка не в формате `#RRGGBB`.
    public static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        let digits = hex.dropFirst()
        guard
            hex.first == "#", digits.count == 6,
            digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
            let value = UInt32(digits, radix: 16)
        else { return nil }
        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    public static func isValid(_ hex: String) -> Bool {
        components(hex) != nil
    }
}
