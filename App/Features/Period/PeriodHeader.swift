import SwiftUI
import ExpenseCore

/// Шапка периода (макеты `01-home`, `03-home-range`, `04-stats`, `05-stats-range`): заголовок-кнопка с ▾
/// открывает шит «Период»; справа чип «Сегодня» (только вне текущего периода, §8 п. 17), пара ‹ › в одной
/// стеклянной капсуле и — на главной — стеклянный ⚙ (пуш настроек, `AppRoute.settings`).
///
/// Заголовок: месяц, год и «Сегодня / Вчера» — словом (на главной Unbounded 28/600, год 20/500 серым; в статистике
/// 22 + 17), даты — «5–7» Unbounded 22/600 + «окт» 17/500 серым. Год — только если не текущий (§8 п. 18).
/// Не переносится: при нехватке места уменьшается (`minimumScaleFactor`), а если и так не помещается —
/// управление уходит строкой ниже (`PeriodHeaderRow`).
///
/// Поля экрана (16 по бокам) задаёт экран. Под шапкой — `PeriodSegment` с отступом 12:
///
///     VStack(spacing: Theme.Spacing.md) {
///         PeriodHeader(selection: period, auraTones: tones)
///         PeriodSegment(selection: period)
///     }
///     .padding(.horizontal, Theme.Spacing.screen)
///
/// Статистика: `PeriodHeader(selection: period, style: .statistics)` — Large Title «Статистика» над периодом, без ⚙.
/// `auraTones` — тона ауры экрана: тот же фон у шита «Период».
struct PeriodHeader: View {
    enum Style {
        /// Главная: заголовок периода крупно, ⚙ справа.
        case home
        /// Статистика: Large Title «Статистика», период 22 + 17, без ⚙.
        case statistics
    }

    @Bindable var selection: PeriodSelection
    var style: Style = .home
    var auraTones: [GouacheTone] = []

    /// Шаги ‹ › и чип «Сегодня» — для отклика `.selection` (сегмент отвечает сам).
    @State private var stepCount = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if style == .statistics {
                Text("stats.title")
                    .typeStyle(.largeTitle)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
            }
            PeriodHeaderRow(
                spacing: Theme.Spacing.sm,
                titleMinimumScale: Self.titleMinimumScale,
                titleFixedWidth: chevronSize + Theme.Spacing.sm
            ) {
                titleButton
                controls
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .animation(Motion.animation(Motion.select, reduceMotion: reduceMotion), value: selection.isCurrent)
        .onAppear { selection.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { selection.refresh() }
        }
        .onCalendarDayChange { selection.refresh() }
        .sheet(isPresented: $selection.isPickerPresented) {
            PeriodSheet(selection: selection, auraTones: auraTones)
        }
    }

    // MARK: - Заголовок

    private var texts: PeriodTexts {
        PeriodTexts(calendar: selection.calendar, now: selection.now)
    }

    private var titleButton: some View {
        Button {
            selection.presentPicker()
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(attributedTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(Self.titleMinimumScale)
                Image(systemName: "chevron.down")
                    .font(.system(size: chevronSize, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(minHeight: Theme.Size.iconButton)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(Motion.PressScale.row))
        .accessibilityLabel(texts.accessibilityLabel(for: selection.period))
        .accessibilityHint(titleHint)
    }

    private var titleHint: LocalizedStringKey {
        selection.mode == .custom ? "header.custom.a11y.hint" : "header.month.a11y.hint"
    }

    /// Части заголовка одним `Text`: масштаб при нехватке места общий для всех частей.
    private var attributedTitle: AttributedString {
        let title = texts.title(for: selection.period)
        var result = AttributedString()
        for part in title.parts {
            let typeStyle = typeStyle(for: part, in: title.style)
            var run = AttributedString(part.text)
            run.font = typeStyle.tabularDigits ? typeStyle.font.monospacedDigit() : typeStyle.font
            run.tracking = typeStyle.trackingEm * typeStyle.size
            run.foregroundColor = part.isSecondary ? Theme.secondary : Theme.ink
            result += run
        }
        return result
    }

    private func typeStyle(for part: PeriodTitle.Part, in titleStyle: PeriodTitle.Style) -> TypeStyle {
        switch (titleStyle, style) {
        case (.word, .home):
            part.isSecondary ? .monthYear : .monthTitle
        case (.word, .statistics), (.dates, _):
            part.isSecondary ? .rangeMonth : .rangeDays
        }
    }

    /// Насколько заголовок уменьшается, прежде чем управление уйдёт строкой ниже (`PeriodHeaderRow`).
    private static let titleMinimumScale: CGFloat = 0.5

    /// ▾ по макету: около половины кегля основной части.
    private var chevronSize: CGFloat {
        style == .home ? TypeStyle.rangeMonth.size : TypeStyle.amountInline.size
    }

    // MARK: - Управление

    private var controls: some View {
        GlassEffectContainer(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                if !selection.isCurrent {
                    todayChip
                }
                GlassStepperPair(
                    previousLabel: LocalizedStringKey(texts.stepLabel(.previous, from: selection.period)),
                    nextLabel: LocalizedStringKey(texts.stepLabel(.next, from: selection.period)),
                    canGoNext: selection.canShowNext,
                    onPrevious: { step { selection.showPrevious() } },
                    onNext: { step { selection.showNext() } }
                )
                if style == .home {
                    NavigationLink(value: AppRoute.settings) {
                        Label("header.settings.a11y", systemImage: "gearshape")
                    }
                    .buttonStyle(.glassCircle())
                }
            }
        }
        .sensoryFeedback(Haptic.selection, trigger: stepCount)
    }

    private func step(_ action: () -> Void) {
        action()
        stepCount += 1
    }

    private var todayChip: some View {
        Button {
            step { selection.showCurrent() }
        } label: {
            Text("header.todayChip")
                .typeStyle(.callout)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(minHeight: Theme.Size.iconButton)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glass(.key)
        .fixedSize()
    }
}

/// Строка шапки: заголовок слева, управление справа. Если заголовку не хватает места даже уменьшенным
/// до `titleMinimumScale` (месяц прошлого года рядом с чипом «Сегодня» и ⚙, крупный текст), управление
/// уходит строкой ниже к правому краю, а заголовок получает всю ширину — вместо «Октябрь 20…».
private struct PeriodHeaderRow: Layout {
    let spacing: CGFloat
    /// `minimumScaleFactor` текста заголовка.
    let titleMinimumScale: CGFloat
    /// Часть заголовка, которая не уменьшается: ▾ и отступ до него.
    let titleFixedWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let title = subviews[0].sizeThatFits(.unspecified)
        let controls = subviews[1].sizeThatFits(.unspecified)
        let width = proposal.width ?? title.width + spacing + controls.width
        if fitsInRow(width: width, title: title, controls: controls) {
            let titleHeight = subviews[0].sizeThatFits(.init(width: width - controls.width - spacing, height: nil)).height
            return CGSize(width: width, height: max(titleHeight, controls.height))
        }
        let titleHeight = subviews[0].sizeThatFits(.init(width: width, height: nil)).height
        return CGSize(width: width, height: titleHeight + spacing + controls.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let title = subviews[0].sizeThatFits(.unspecified)
        let controls = subviews[1].sizeThatFits(.unspecified)
        if fitsInRow(width: bounds.width, title: title, controls: controls) {
            let titleWidth = bounds.width - controls.width - spacing
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                              proposal: .init(width: titleWidth, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
        } else {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                              proposal: .init(width: bounds.width, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.maxY), anchor: .bottomTrailing, proposal: .unspecified)
        }
    }

    private func fitsInRow(width: CGFloat, title: CGSize, controls: CGSize) -> Bool {
        let minimumTitle = (title.width - titleFixedWidth) * titleMinimumScale + titleFixedWidth
        return minimumTitle + spacing + controls.width <= width
    }
}

#if DEBUG
#Preview("Шапка периода") {
    @Previewable @State var home = PeriodSelection()
    @Previewable @State var stats = PeriodSelection(kind: .week)
    NavigationStack {
        VStack(spacing: Theme.Spacing.xl) {
            PeriodHeader(selection: home)
            PeriodHeader(selection: stats, style: .statistics)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AuraBackground(tones: [.shalfey, .abrikos]).ignoresSafeArea())
    }
}
#endif
