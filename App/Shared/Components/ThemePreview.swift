#if DEBUG
import SwiftUI

/// Превью компонента в светлой и тёмной теме рядом, на фоне экрана.
struct ThemePreview<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            panel(.light)
            panel(.dark)
        }
    }

    private func panel(_ scheme: ColorScheme) -> some View {
        content()
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(Theme.canvas)
            .environment(\.colorScheme, scheme)
    }
}
#endif
