import SwiftUI

/// «Лицензии» (§8 п. 8): два блока — иконки MingCute (Apache 2.0) и шрифт Unbounded (OFL 1.1).
/// Над полным английским текстом лицензии — строка по-русски (`settings.licenses`, `settings.licenses.fonts`).
struct LicensesView: View {
    /// Строка по-русски и файл лицензии в бандле (`App/Resources/Licenses`, `App/Resources/Fonts`).
    private static let blocks: [(title: LocalizedStringKey, file: String)] = [
        ("settings.licenses", "MingCute-LICENSE"),
        ("settings.licenses.fonts", "OFL")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayout.groupSpacing) {
                ForEach(Self.blocks, id: \.file) { block in
                    SettingsGroup(header: block.title) {
                        Text(verbatim: Self.licenseText(block.file))
                            .typeStyle(.footnote)
                            .monospaced()
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.lg)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background(Theme.canvas)
        .navigationTitle("settings.about.licenses")
        .navigationBarTitleDisplayMode(.large)
    }

    /// Текст лицензии из бандла; без файла — пусто (файлы кладёт сборка, см. `App/Resources`).
    private static func licenseText(_ name: String) -> String {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LicensesView()
    }
}
#endif
