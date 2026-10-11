import SwiftUI
import ExpenseCore

/// Верх бумажного листа в виде «Плитки» (`01-home`, `03-home-range`): итог Unbounded 40 + символ валюты 20,
/// фраза-сравнение SF 15 (выделение — SF 600 графитом), treemap категорий 358 × 208.
struct HomeTilesSummary: View {
    let content: HomeContent
    /// `nil` — сравнивать не с чем (`StatsTrend.incomparable`): строки нет.
    let comparison: SummaryTexts.Comparison?
    let texts: HomeTexts
    let periodName: String
    let onSelect: (CategoryVizItemID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeTotal(totalMinor: content.summary.totalMinor, texts: texts)
            if let comparison {
                HomeComparisonText(comparison: comparison, emphasis: TypeStyle.callout)
                    .typeStyle(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.md)
                    .contentTransition(.opacity)
            }
            CategoryTilesView(homeData: content.overview, periodName: periodName, onSelect: onSelect)
                .padding(.top, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// «Кольцо» на ауре над листом (`02-home-ring`): итог и фраза SF 13 в центре.
/// С размера текста `phraseBelowFrom` фраза в центр не помещается (строки шире хорды круга, на AX — и выше кольца) —
/// уходит под кольцо, как сумма под текст в `ExpenseRow`.
struct HomeRingSummary: View {
    let content: HomeContent
    /// `nil` — сравнивать не с чем (`StatsTrend.incomparable`): фразы нет.
    let comparison: SummaryTexts.Comparison?
    let periodName: String
    let onSelect: (CategoryVizItemID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let phraseBelowFrom = DynamicTypeSize.xxLarge

    var body: some View {
        let isPhraseBelow = dynamicTypeSize >= Self.phraseBelowFrom
        VStack(spacing: Theme.Spacing.md) {
            HomeCategoryRing(data: content.overview, periodName: periodName, onSelect: onSelect) {
                if let comparison, !isPhraseBelow {
                    HomeComparisonText(comparison: comparison, emphasis: TypeStyle.footnoteStrong)
                        .contentTransition(.opacity)
                }
            }
            if let comparison, isPhraseBelow {
                HomeComparisonText(comparison: comparison, emphasis: TypeStyle.footnoteStrong)
                    .typeStyle(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
        }
    }
}

/// Фраза-сравнение с выделением; VoiceOver читает её с суммой словами («на 38 рублей меньше…»).
/// Шрифт выделения разрешается в окружении самой фразы: в центре кольца действует предел Dynamic Type
/// (`vizDynamicTypeLimit`), и шрифт из окружения экрана дал бы выделение крупнее остальной фразы.
private struct HomeComparisonText: View {
    let comparison: SummaryTexts.Comparison
    let emphasis: TypeStyle

    @Environment(\.fontResolutionContext) private var fontContext

    var body: some View {
        Text(HomePhrase.styled(comparison.text, emphasis: emphasis, in: fontContext))
            .accessibilityLabel(Text(verbatim: comparison.spoken))
    }
}

/// Итог периода: Unbounded 40 + символ валюты 20 secondary, цифры прокручиваются (`number`).
private struct HomeTotal: View {
    let totalMinor: Int64
    let texts: HomeTexts

    var body: some View {
        AmountText(
            text: texts.money.string(fromMinor: totalMinor, style: .plain),
            value: Double(totalMinor),
            size: .total,
            currency: texts.money.currencySymbol,
            accessibilityText: texts.shared.spoken(totalMinor)
        )
        .minimumScaleFactor(0.5)
    }
}

/// Первый запуск (`home.empty.firstRun`): на листе вместо итога, обзора и ленты — Headline и строка SF 15.
struct HomeFirstRun: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("home.empty.firstRun.title")
                .typeStyle(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Text("home.empty.firstRun.body")
                .typeStyle(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Период без трат (`home.empty.period.*`): «пока нет» / «не было» и стеклянная капсула 44
/// «К последней трате» — открывает период последней траты.
struct HomeEmptyPeriod: View {
    let message: String
    let onShowLatest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(verbatim: message)
                .typeStyle(.callout)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("home.empty.period.action", action: onShowLatest)
                .buttonStyle(.glassCapsule(.glass, height: Theme.Size.chip, expands: false))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Выделение во фразе из `L10n.attributed`: выделенная часть — SF 600 с табличными цифрами графитом
/// («Правило денег»: сумма внутри SF-фразы — SF 600), остальное — шрифт (`typeStyle`) и цвет `Text`.
/// Шрифт фрагмента — через `CurrencySignFont`, иначе знак рубля в сумме будет квадратом
/// (`context` — `@Environment(\.fontResolutionContext)`).
enum HomePhrase {
    static func styled(_ text: AttributedString, emphasis: TypeStyle, in context: Font.Context) -> AttributedString {
        var result = text
        let font = CurrencySignFont.font(emphasis.font.monospacedDigit(), in: context)
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            result[run.range].inlinePresentationIntent = nil
            result[run.range].font = font
            result[run.range].foregroundColor = Theme.ink
        }
        return result
    }
}
