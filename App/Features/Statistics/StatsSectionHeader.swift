import SwiftUI

/// Размеры экрана статистики с макетов `04-stats`, `05-stats-range`, которых нет в токенах. Менять здесь.
nonisolated enum StatsLayout {
    /// Между блоками на листе («Категории», «По дням», «Темп»…).
    static let sectionSpacing: CGFloat = 2 * Theme.Spacing.xl
    /// Насколько бумажный лист уходит за низ содержимого: под таб-бар и при оттягивании прокрутки.
    static let sheetOverscroll: CGFloat = 1_000
    /// Переход из главной: категория раскрывается после смены вкладки — чтобы было видно анимацию.
    static let focusExpansionDelay: Duration = .milliseconds(350)
    /// Пометка «только Продукты»: место справа от заголовка (copy.json → `viz.drill.filter`, risk: 150 px).
    static let filterMarkWidth: CGFloat = 150
    /// Столбики «По дням»: высота поля и место над ним под стеклянную подсказку дня.
    static let barsHeight: CGFloat = 96
    static let tooltipSpace: CGFloat = 40
    /// Столбик — доля ширины дня; будущий день — чёрточка этой высоты.
    static let barWidthRatio: CGFloat = 0.56
    static let barCorner: CGFloat = 2
    static let futureDashHeight: CGFloat = 3
    /// «Темп»: высота поля, место справа под подписи у концов кривых, толщины линий.
    static let paceHeight: CGFloat = 150
    static let paceTrailingSpace: CGFloat = 64
    /// Место под подписями оси «Темпа».
    static let paceAxisSpace: CGFloat = 24
    static let paceCurrentLine: CGFloat = 3
    static let pacePreviousLine: CGFloat = 2.5
    static let paceForecastLine: CGFloat = 2.5
    static let pacePoint: CGFloat = 9
    /// Образец линии в легенде «Темпа».
    static let legendSwatch = CGSize(width: 16, height: 3)
    /// «Привычки»: плитка дня недели и зазор.
    static let habitTileHeight: CGFloat = 80
    static let habitGap: CGFloat = 4
    /// «2026 по дням»: зазоры клеток, обводка «сегодня».
    static let yearCellGap: CGFloat = 1.5
    static let yearRowGap: CGFloat = 3
    static let yearCellRadius: CGFloat = 1.5
    static let yearTodayLine: CGFloat = 1.5
}

/// Заголовок блока на листе: SF 22/600 слева, справа — пометка «только Продукты» и подпись единиц
/// («в среднем за день, ⃅») SF 15 secondary.
struct StatsSectionHeader: View {
    let title: Text
    var filterMark: String?
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            title
                .typeStyle(.title)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.sm)
            if filterMark != nil || note != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if let filterMark {
                        StatsFilterMark(text: filterMark)
                    }
                    if let note {
                        Text(verbatim: note)
                            .lineLimit(1)
                    }
                }
                .typeStyle(.subheadline)
                .foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// «только Продукты»: блок отфильтрован раскрытой категорией. Длинное имя обрезается в конце.
struct StatsFilterMark: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .typeStyle(.subheadline)
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: StatsLayout.filterMarkWidth, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Пустой блок «мало данных» (`stats.fewData.*`): строка SF 15 secondary вместо графика.
struct StatsFewDataLine: View {
    let key: LocalizedStringKey

    var body: some View {
        Text(key)
            .typeStyle(.subheadline)
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Фраза SF 15 secondary с выделением `**…**` из каталога: ключевая часть — SF 600 графитом (DESIGN.md).
/// Шрифт фрагмента — со знаком рубля в подстановке (`TypeStyle.font(in:)`), иначе «⃅» в сумме — квадрат.
struct StatsPhrase: View {
    let text: AttributedString
    @Environment(\.fontResolutionContext) private var fontContext

    var body: some View {
        Text(styled)
            .typeStyle(.subheadline)
            .foregroundStyle(Theme.secondary)
    }

    private var styled: AttributedString {
        var styled = text
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            styled[run.range].inlinePresentationIntent = nil
            styled[run.range].font = TypeStyle.callout.font(in: fontContext)
            styled[run.range].foregroundColor = Theme.ink
        }
        return styled
    }
}
