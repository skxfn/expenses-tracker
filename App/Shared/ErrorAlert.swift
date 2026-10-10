import SwiftUI
import ExpenseCore

extension View {
    /// Системный алерт ошибки сохранения: заголовок `global.saveError.title`, текст — `message`, «ОК».
    /// Закрытие сбрасывает `message` в `nil`. Текст готовить через `UserFacingError.message(for:)`.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            Text("global.saveError.title"),
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented { message.wrappedValue = nil }
                }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("error.alert.ok", role: .cancel) {}
        } message: { text in
            Text(verbatim: text)
        }
    }
}

/// Текст ошибки для пользователя — только из `copy.json`. Тексты Core (`errorDescription`)
/// в интерфейс не попадают (INTEGRATION §4.4).
enum UserFacingError {
    static func message(for error: any Error) -> String {
        guard let error = error as? ExpenseStoreError else {
            return String(localized: "global.saveError.message")
        }
        switch error {
        case .invalidAmount: return String(localized: "error.store.invalidAmount")
        case .emptyCategoryName: return String(localized: "error.store.emptyCategoryName")
        case .duplicateCategoryName(let name): return L10n.format("error.store.duplicateCategoryName", name)
        case .invalidColorHex: return String(localized: "error.store.invalidColorHex")
        case .invalidReassignTarget: return String(localized: "error.store.invalidReassignTarget")
        case .categoryLimitReached: return String(localized: "cat.group.limit")
        case .hasSubcategories: return String(localized: "cat.typeSwitch.block")
        case .invalidParent: return String(localized: "global.saveError.message")
        }
    }
}
