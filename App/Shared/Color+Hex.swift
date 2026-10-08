import SwiftUI
import ExpenseCore

extension Color {
    /// Цвет из строки `#RRGGBB`. Для некорректной строки — системный серый.
    init(hex: String) {
        if let components = HexColor.components(hex) {
            self.init(red: components.red, green: components.green, blue: components.blue)
        } else {
            self = .gray
        }
    }
}
