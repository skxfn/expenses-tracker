import SwiftUI
import ExpenseCore

/// Верх бумажного листа в виде «Плитки» (`01-home`, `03-home-range`): итог Unbounded 40 + символ валюты 20,
/// фраза-сравнение SF 15 (выделение — SF 600 графитом), treemap категорий 358 × 208.
struct HomeTilesSummary: View {
    let content: HomeContent
    let comparison: AttributedString
    let texts: HomeTexts
    let periodName: String
    let onSelect: (CategoryVizItemID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeTotal(totalMinor: content.summary.totalMinor, texts: texts)
            Text(HomePhrase.styled(comparison, emphasis: TypeStyle.callout))
                .typeStyle(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.sm)
                .contentTransition(.opacity)
            CategoryTilesView(homeData: content.overview, periodName: periodName, onSelect: onSelect)
                .padding(.top, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// «Кольцо» на ауре над листом (`02-home-ring`): итог и фраза SF 13 в центре.
struct HomeRingSummary: View {
    let content: HomeContent
    let comparison: AttributedString
    let periodName: String
    let onSelect: (CategoryVizItemID) -> Void

    var body: some View {
        HomeCategoryRing(data: content.overview, periodName: periodName, onSelect: onSelect) {
            Text(HomePhrase.styled(comparison, emphasis: TypeStyle.footnoteStrong))
                .contentTransition(.opacity)
        }
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
            accessibilityText: texts.spoken(totalMinor)
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
/// («Правило денег»: сумма внутри SF-фразы — SF 600), остальное — шрифт и цвет `Text`.
enum HomePhrase {
    static func styled(_ text: AttributedString, emphasis: TypeStyle) -> AttributedString {
        var result = text
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            result[run.range].inlinePresentationIntent = nil
            result[run.range].font = emphasis.font.monospacedDigit()
            result[run.range].foregroundColor = Theme.ink
        }
        return result
    }
}
