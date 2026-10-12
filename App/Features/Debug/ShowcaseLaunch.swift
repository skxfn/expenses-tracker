#if DEBUG
import SwiftUI

/// Страницы DEBUG-витрины и спайков. Открыть: launch-аргумент `-debugShowcase YES` (оглавление)
/// или `-debugShowcase <страница>` — сразу страницу (для скриншотов без касаний).
enum ShowcasePage: String, CaseIterable, Identifiable {
    case tokens, tones, components, glass, fonts, currencySign
    case tabBarSystem, tabBarNative, tabBarLens, tabBarCustom, feed, addSheet
    case viz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tokens: "Токены"
        case .tones: "«Гуашь»: роли и ступени"
        case .components: "Компоненты"
        case .glass: "Стекло и кнопки"
        case .fonts: "Unbounded: регистрация и tnum"
        case .currencySign: "Знак рубля: подстановка"
        case .tabBarSystem: "Спайк: системный TabView + «+»"
        case .tabBarNative: "Спайк: системный TabView, «+» — Tab(role: .search)"
        case .tabBarLens: "Спайк: свой бар с линзой (касание, перетаскивание)"
        case .tabBarCustom: "Спайк: свой бар поверх TabView"
        case .feed: "Спайк: лента на List"
        case .addSheet: "Спайк: шит записи (зум, клавиатура)"
        case .viz: "Визуализации категорий"
        }
    }

    /// Страница, которой нужен весь экран (без NavigationStack витрины).
    var isFullScreen: Bool {
        switch self {
        case .tabBarSystem, .tabBarNative, .tabBarLens, .tabBarCustom, .feed, .addSheet: true
        default: false
        }
    }
}

enum ShowcaseLaunch {
    /// `nil` — витрина не запрошена; `.some(nil)` — оглавление.
    static func requested(defaults: UserDefaults = .standard) -> ShowcasePage?? {
        guard let value = defaults.string(forKey: "debugShowcase") else { return nil }
        if let page = ShowcasePage(rawValue: value) { return .some(page) }
        return defaults.bool(forKey: "debugShowcase") ? .some(nil) : nil
    }
}

extension View {
    /// DEBUG: заменяет корень приложения витриной, если передан `-debugShowcase`.
    func debugShowcase() -> some View {
        modifier(ShowcaseLaunchModifier(request: ShowcaseLaunch.requested()))
    }
}

private struct ShowcaseLaunchModifier: ViewModifier {
    let request: ShowcasePage??

    func body(content: Content) -> some View {
        switch request {
        case .none:
            content
        case .some(.none):
            ShowcaseIndex()
        case .some(.some(let page)):
            if page.isFullScreen {
                ShowcaseDestination(page: page)
            } else {
                NavigationStack { ShowcaseDestination(page: page) }
            }
        }
    }
}

/// Оглавление витрины.
struct ShowcaseIndex: View {
    var body: some View {
        NavigationStack {
            List(ShowcasePage.allCases) { page in
                NavigationLink(page.title) { ShowcaseDestination(page: page) }
            }
            .navigationTitle("Витрина")
        }
    }
}

struct ShowcaseDestination: View {
    let page: ShowcasePage

    var body: some View {
        switch page {
        case .tokens: TokensShowcase()
        case .tones: TonesShowcase()
        case .components: ComponentsShowcase()
        case .glass: GlassShowcase()
        case .fonts: FontsShowcase()
        case .currencySign: CurrencySignShowcase()
        case .tabBarSystem: TabBarSystemSpike()
        case .tabBarNative: TabBarNativeSpike()
        case .tabBarLens: TabBarLensSpike()
        case .tabBarCustom: TabBarCustomSpike()
        case .feed: FeedSpike()
        case .addSheet: AddSheetSpike()
        case .viz: CategoryVizShowcase()
        }
    }
}
#endif
