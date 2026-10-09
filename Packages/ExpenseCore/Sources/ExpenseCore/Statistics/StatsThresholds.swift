/// Пороги статистики в одном месте. Владелец их не задавал (design/INTEGRATION.md §8, п. 11):
/// приняты рекомендации из §8, менять — здесь.
public enum StatsThresholds {
    /// Категории с долей меньше этой сворачиваются в «Ещё N».
    public static let foldShare = 0.03
    /// …но только если таких категорий хотя бы столько.
    public static let foldMinimumCount = 2
    /// «примерно как …»: |итог − прошлый| / прошлый меньше этого.
    public static let sameChange = 0.01
    /// «почти поровну» в будни и выходные: разница средних меньше этой доли от большей.
    public static let weekSplitTie = 0.10
    /// «Темп»: прошло дней периода (включая сегодня) не меньше…
    public static let paceMinimumDays = 3
    /// …и трат за них не меньше.
    public static let paceMinimumCount = 3
    /// «Привычки»: траты хотя бы в стольких разных днях.
    public static let habitsMinimumDays = 7
    /// Прогноз округляется до стольких значащих цифр («≈ 1 600»).
    public static let forecastSignificantDigits = 2
}
