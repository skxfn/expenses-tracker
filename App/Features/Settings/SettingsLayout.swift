import SwiftUI
import ExpenseCore

/// Общие размеры экранов «в стиле настроек» (DESIGN.md → Layout: строки 52–56, группы r 22).
enum SettingsLayout {
    /// Между группами: заголовок следующей группы отделён от предыдущей сноски или группы.
    static let groupSpacing: CGFloat = Theme.Spacing.xl + Theme.Spacing.sm
    /// Строка группы.
    static let rowHeight: CGFloat = Theme.Size.field
}

/// Группа со сноской из данных («Последняя копия: 1 окт»): у `SettingsGroup` сноска — только ключ каталога.
/// Вид сноски тот же: SF 13 secondary с отступом 16.
struct SettingsFootnoted<Content: View>: View {
    let footnote: String?
    @ViewBuilder let content: Content

    init(_ footnote: String?, @ViewBuilder content: () -> Content) {
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            content
            if let footnote {
                Text(verbatim: footnote)
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// Фон экрана «в стиле настроек»: бумага-фон и аура тонов (если есть) в верхней трети.
    func settingsBackground(tones: [GouacheTone] = []) -> some View {
        background {
            AuraBackground(tones: tones)
                .ignoresSafeArea()
        }
    }
}
