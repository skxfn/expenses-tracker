import SwiftUI

extension View {
    /// Алерт с текстом ошибки. Закрытие сбрасывает `message` в `nil`.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Не получилось",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented { message.wrappedValue = nil }
                }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }
}
