import SwiftUI
import ExpenseCore

/// Шапка периода (макеты `01-home`, `03-home-range`, `04-stats`, `05-stats-range`): заголовок-кнопка с ▾
/// открывает шит «Период»; справа чип «Сегодня» (только вне текущего периода, §8 п. 17), пара ‹ › в одной
/// стеклянной капсуле и — на главной — стеклянный ⚙ (пуш настроек, `AppRoute.settings`).
///
/// Заголовок: месяц, год и «Сегодня / Вчера» — словом (на главной Unbounded 28/600, год 20/500 серым; в статистике
/// 22 + 17), даты — «5–7» Unbounded 22/600 + «окт» 17/500 серым. Год — только если не текущий (§8 п. 18).
/// Не переносится: при нехватке места уменьшается (`minimumScaleFactor`).
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
            HStack(spacing: Theme.Spacing.sm) {
                titleButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                controls
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .animation(Motion.animation(Motion.select, reduceMotion: reduceMotion), value: selection.isCurrent)
        .onAppear { selection.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { selection.refresh() }
        }
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
                    .minimumScaleFactor(0.5)
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
