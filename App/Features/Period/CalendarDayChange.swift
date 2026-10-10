import Foundation
import SwiftUI

extension View {
    /// Наступил новый календарный день, пока приложение открыто (полночь, смена часового пояса):
    /// «сегодня», текущий период и месяц календаря пересчитываются. `NSCalendarDayChanged` приходит
    /// не обязательно на главном потоке.
    func onCalendarDayChange(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)) { _ in
            action()
        }
    }
}
