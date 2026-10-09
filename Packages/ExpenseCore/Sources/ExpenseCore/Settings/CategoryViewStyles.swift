/// Обзор категорий на вкладке «Траты» (`SettingsKeys.homeOverviewStyle`), выбирается в настройках.
/// Для `@AppStorage`: значение хранится как `rawValue`.
public enum HomeOverviewStyle: String, CaseIterable, Sendable {
    /// «Плитки».
    case tiles
    /// «Кольцо».
    case ring

    public static let `default` = HomeOverviewStyle.tiles
}

/// Вид раздела категорий в статистике (`SettingsKeys.statsCategoryView`), запоминается.
/// Порядок случаев — порядок в переключателе: «Плитки · Полосы · Солнце · Кольцо».
public enum StatsCategoryView: String, CaseIterable, Sendable {
    case tiles
    case strips
    case sun
    case ring

    public static let `default` = StatsCategoryView.tiles
}
