import SwiftUI

/// Экран вместо приложения, если хранилище не открылось (`launch.error.*`), в стиле настроек.
/// Данные при этом не удаляются: экран только объясняет, что делать, и показывает причину.
struct StoreErrorView: View {
    let failure: StoreFailure

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("launch.error.title")
                            .typeStyle(.title)
                            .foregroundStyle(Theme.ink)
                        Text("launch.error.body")
                            .typeStyle(.body)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    SettingsGroup(header: "launch.error.reason") {
                        detail(failure.summary, monospaced: false)
                    }
                    SettingsGroup(header: "launch.error.details") {
                        detail(failure.details, monospaced: true)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.lg)
            }
            .background(Theme.canvas)
            .navigationTitle("launch.error.navTitle")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func detail(_ text: String, monospaced: Bool) -> some View {
        Text(verbatim: text)
            .typeStyle(monospaced ? .footnote : .body)
            .monospaced(monospaced)
            .foregroundStyle(Theme.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
    }
}

#if DEBUG
#Preview {
    StoreErrorView(failure: StoreFailure(CocoaError(.fileReadCorruptFile)))
}
#endif
