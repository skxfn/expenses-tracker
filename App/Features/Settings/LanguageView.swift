import SwiftData
import SwiftUI
import ExpenseCore

/// Строка «Язык» в группе «О приложении»: выбранный язык и переход к экрану «Язык».
struct LanguageSettingsRow: View {
    @State private var preference = LanguageModel.storedPreference()

    var body: some View {
        NavigationLink {
            LanguageView()
        } label: {
            SettingsRow("settings.language", value: L10n.format(preference.titleKey), showsChevron: true)
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
        .accessibilityLabel(Text("settings.language"))
        .accessibilityValue(Text(LocalizedStringKey(preference.titleKey)))
        // Выбор меняется на экране «Язык» — после возврата перечитать.
        .onAppear { preference = LanguageModel.storedPreference() }
    }
}

/// Экран «Язык» (`settings.language`, макета нет — в стиле выбора валюты): язык приложения
/// («Как в системе» / «Русский» / «English», со следующего запуска) и названия категорий по умолчанию
/// (переводятся сразу, только непереименованные). Группа категорий — только если такие категории есть.
struct LanguageView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = LanguageModel()

    var body: some View {
        ScrollView {
            VStack(spacing: SettingsLayout.groupSpacing) {
                SettingsGroup {
                    ForEach(LanguagePreference.allCases, id: \.self) { preference in
                        LanguageChoiceRow(titleKey: preference.titleKey, isSelected: model.preference == preference) {
                            model.select(preference)
                        }
                    }
                }
                if model.hasDefaultCategories {
                    SettingsGroup(header: "settings.language.categories", footer: "settings.language.categories.footer") {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            LanguageChoiceRow(
                                titleKey: language.titleKey,
                                isSelected: model.categoryStatus[language]?.isCurrent == true
                            ) {
                                model.translateCategories(to: language, context: modelContext)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background(Theme.canvas)
        .navigationTitle("settings.language")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { model.refresh(context: modelContext) }
        .alert(
            Text("settings.language.restart.title"),
            isPresented: Binding(
                get: { model.restartPrompt != nil },
                set: { if !$0 { model.restartPrompt = nil } }
            ),
            presenting: model.restartPrompt
        ) { prompt in
            if prompt.canTranslateCategories {
                Button("settings.language.restart.translate") {
                    model.translateCategories(to: prompt.language, context: modelContext)
                }
                Button("settings.language.restart.keep", role: .cancel) {}
            } else {
                Button("error.alert.ok", role: .cancel) {}
            }
        } message: { prompt in
            if prompt.canTranslateCategories {
                Text("settings.language.restart.categories")
            } else {
                Text("settings.language.restart.message")
            }
        }
        .errorAlert($model.errorMessage)
    }
}

/// Строка выбора с галочкой справа, как в выборе валюты.
private struct LanguageChoiceRow: View {
    let titleKey: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRow(title: LocalizedStringKey(titleKey)) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .typeStyle(.headline)
                        .foregroundStyle(Theme.ink)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LanguageView()
    }
    .modelContainer(try! ModelContainerFactory.make(inMemory: true))
}
#endif
