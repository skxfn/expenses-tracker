import SwiftUI

/// Prominent-действие справа в шапке шита («Готово» в редакторе категории).
struct SheetConfirmAction {
    let title: LocalizedStringKey
    var isEnabled = true
    let action: () -> Void
}

extension View {
    /// Шапка шита (§6, §8 п. 6): системный ✕ слева (`ButtonRole.close`, iOS 26), заголовок SF 17/600 по центру,
    /// ✓ сверху нет. `confirm` — одно prominent-действие справа. Радиус шита системный.
    /// Применять к содержимому внутри `NavigationStack` шита.
    func sheetHeader(
        _ title: LocalizedStringKey,
        onClose: @escaping () -> Void,
        confirm: SheetConfirmAction? = nil
    ) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close, action: onClose)
                }
                if let confirm {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirm.title, action: confirm.action)
                            .prominentGlassButtonStyle()
                            .disabled(!confirm.isEnabled)
                    }
                }
            }
    }
}

#if DEBUG
#Preview("Шапка шита") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            NavigationStack {
                Theme.canvasElevated
                    .ignoresSafeArea()
                    .sheetHeader("Новая подкатегория", onClose: {}, confirm: SheetConfirmAction(title: "Готово") {})
            }
        }
}
#endif
