import SwiftData
import SwiftUI

extension View {
    /// Данные сохранены (`ModelContext.didSave`) контекстом экрана из окружения — общая подписка экранов на изменения базы.
    ///
    /// Синхронно, в момент сохранения, а не следующим проходом главного цикла: до перерисовки модель экрана уже
    /// перечитана. Иначе кадр между снятием пометки `PendingDeletion` (до сохранения) и новой выборкой показывает
    /// удалённую строку и старые итоги, а прокрутка к только что записанной трате её не находит.
    /// Только уведомления этого контекста (`object:`): главный контекст сохраняет на главном потоке, поэтому
    /// `perform` вызывается только там; сохранения других (фоновых) контекстов сюда не приходят.
    func onDataSaved(perform action: @escaping () -> Void) -> some View {
        modifier(DataSaveObserver(action: action))
    }
}

private struct DataSaveObserver: ViewModifier {
    let action: () -> Void
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave, object: modelContext)) { _ in
            action()
        }
    }
}
