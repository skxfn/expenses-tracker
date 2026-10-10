import SwiftUI

extension View {
    /// Тост отмены удаления (INTEGRATION §2.2, §4.9) у нижнего края содержимого — над таб-баром на всех вкладках:
    /// «Удалено · Отменить», 4 с, таймер стоит, пока палец на тосте. VoiceOver объявляет удаление и отмену.
    func deletionToast(_ pendingDeletion: PendingDeletion) -> some View {
        modifier(DeletionToastModifier(pendingDeletion: pendingDeletion))
    }
}

private struct DeletionToastModifier: ViewModifier {
    let pendingDeletion: PendingDeletion

    func body(content: Content) -> some View {
        content
            .glassToast(isPresented: pendingDeletion.item != nil) {
                GlassToast(
                    message: "toast.deleted.title",
                    action: .init(title: "toast.deleted.undo", handler: undo),
                    onPressingChanged: { isPressing in
                        if isPressing { pendingDeletion.pause() } else { pendingDeletion.resume() }
                    }
                )
                .accessibilityAction(named: "toast.deleted.a11y.undo", undo)
            }
            .onChange(of: pendingDeletion.item?.id) { _, id in
                guard id != nil else { return }
                announce("toast.deleted.a11y")
            }
    }

    private func undo() {
        pendingDeletion.undo()
        announce("toast.undone.a11y")
    }

    private func announce(_ key: String.LocalizationValue) {
        AccessibilityNotification.Announcement(String(localized: key)).post()
    }
}
