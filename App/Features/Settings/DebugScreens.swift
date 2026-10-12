#if DEBUG
import SwiftData
import SwiftUI
import ExpenseCore

/// Экраны настроек и категорий сразу при запуске — для скриншотов без касаний (launch-аргумент
/// `-debugScreen <экран>`). Вместе с `-demoData YES` данные те же, что в приложении;
/// `-debugScroll bottom` открывает прокрутку с конца (нижняя часть длинных экранов).
enum DebugScreen: String {
    case settings, categories, currency
    /// Правка подкатегории «Кофе» (или первой подкатегории) — сверка с макетом `11-category`.
    case category
    /// Новая категория верхнего уровня (режим «Категория»: 15 образцов «Гуаши»).
    case newCategory
    /// Новая подкатегория «Кафе».
    case newSubcategory
    /// Восстановление из копии текущих данных (шит до выбора режима).
    case importSheet = "import"
    /// Перенос трат из Monefy: CSV по пути из `-debugMonefyFile <путь>` (шит сопоставления или алерт ошибки чтения).
    /// `-debugMonefyMapping auto` — несопоставленные категории Monefy по порядку в категории приложения, последняя —
    /// «Без категории»; `-debugMonefyImport YES` — сразу перенести (отчёт).
    case monefy
    /// Экран сбоя запуска с примерной ошибкой.
    case launchError

    static func requested(defaults: UserDefaults = .standard) -> DebugScreen? {
        defaults.string(forKey: "debugScreen").flatMap(DebugScreen.init(rawValue:))
    }

    /// Начальная точка прокрутки из `-debugScroll bottom`.
    static func scrollAnchor(defaults: UserDefaults = .standard) -> UnitPoint? {
        defaults.string(forKey: "debugScroll") == "bottom" ? .bottom : nil
    }
}

extension View {
    /// DEBUG: заменяет корень приложения экраном из `-debugScreen`. Ставить под `.modelContainer`.
    func debugScreen() -> some View {
        modifier(DebugScreenModifier(screen: DebugScreen.requested()))
    }
}

private struct DebugScreenModifier: ViewModifier {
    let screen: DebugScreen?

    func body(content: Content) -> some View {
        if let screen {
            DebugScreenRoot(screen: screen)
        } else {
            content
        }
    }
}

private struct DebugScreenRoot: View {
    let screen: DebugScreen

    @AppStorage(SettingsKeys.currencyCode) private var currencyCode = CurrencySettings.fallbackCode
    @AppStorage(SettingsKeys.currencySymbolStyle) private var symbolStyle = CurrencySymbolStyle.default
    @Environment(\.modelContext) private var modelContext
    @State private var editorMode: CategoryEditorMode?
    @State private var importSession: ImportSession?
    @State private var monefySession: MonefyImportSession?
    @State private var alert: FailureAlert?

    var body: some View {
        Group {
            if screen == .launchError {
                StoreErrorView(failure: StoreFailure(CocoaError(.fileReadCorruptFile)))
            } else {
                NavigationStack { root }
            }
        }
        .environment(\.moneyFormatter, MoneyFormatter(currencyCode: currencyCode, locale: .app, symbolStyle: symbolStyle))
        .sheet(item: $editorMode) { mode in
            CategoryEditorSheet(mode: mode)
                .defaultScrollAnchor(DebugScreen.scrollAnchor())
        }
        .sheet(item: $importSession) { session in
            ImportView(session: session)
                .defaultScrollAnchor(DebugScreen.scrollAnchor())
        }
        .sheet(item: $monefySession) { session in
            MonefyImportView(session: session)
                .defaultScrollAnchor(DebugScreen.scrollAnchor())
        }
        .failureAlert($alert)
        .defaultScrollAnchor(DebugScreen.scrollAnchor())
        .onAppear(perform: present)
    }

    @ViewBuilder
    private var root: some View {
        switch screen {
        case .settings, .importSheet, .monefy, .launchError: SettingsView()
        case .currency: CurrencyPickerView()
        case .categories, .category, .newCategory, .newSubcategory: CategoriesView()
        }
    }

    private func present() {
        let store = ExpenseStore(context: modelContext)
        let all = (try? store.allCategories()) ?? []
        switch screen {
        case .category:
            let target = all.first { $0.name == "Кофе" && $0.parent != nil } ?? all.first { $0.parent != nil } ?? all.first
            editorMode = target.map { .edit(categoryID: $0.id) }
        case .newCategory:
            editorMode = .create()
        case .newSubcategory:
            let parent = all.first { $0.name == "Кафе" && $0.parent == nil } ?? all.first { $0.parent == nil }
            editorMode = .create(parentID: parent?.id)
        case .importSheet:
            guard
                let data = try? BackupExporter.exportData(from: modelContext, currencyCode: currencyCode),
                let payload = try? BackupImporter.decode(data)
            else { return }
            importSession = ImportSession(payload: payload)
        case .monefy:
            let defaults = UserDefaults.standard
            let session: MonefyImportSession
            do {
                let data = try Data(contentsOf: URL(filePath: defaults.string(forKey: "debugMonefyFile") ?? ""))
                session = try BackupModel.monefySession(data: data, context: modelContext)
            } catch {
                alert = .monefyRead(error)
                return
            }
            if defaults.string(forKey: "debugMonefyMapping") == "auto" {
                let topLevel = all.filter { $0.parent == nil && !$0.isArchived }
                for (index, group) in session.plan.groups.enumerated() where session.mapping[group.name] == nil {
                    let isLast = index == session.plan.groups.count - 1
                    let target: MonefyCategoryTarget = isLast || index >= topLevel.count ? .uncategorized : .category(topLevel[index].id)
                    session.select(target, for: group.name)
                }
            }
            monefySession = session
            if defaults.bool(forKey: "debugMonefyImport") {
                Task { await session.apply(context: modelContext) }
            }
        case .settings, .categories, .currency, .launchError:
            break
        }
    }
}
#endif
