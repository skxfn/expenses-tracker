import SwiftUI

/// Экран вместо приложения, если хранилище не открылось. Данные при этом не удаляются.
struct StoreErrorView: View {
    let failure: StoreFailure

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ContentUnavailableView {
                        Label("Не удалось открыть данные", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Ваши траты не удалены. Попробуйте перезапустить приложение. Если ошибка повторяется — обновите приложение, не удаляя его.")
                    }
                }
                Section("Причина") {
                    Text(failure.summary)
                        .textSelection(.enabled)
                }
                Section("Подробности для разработчика") {
                    Text(failure.details)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Ошибка")
        }
    }
}

#Preview {
    StoreErrorView(failure: StoreFailure(CocoaError(.fileReadCorruptFile)))
}
