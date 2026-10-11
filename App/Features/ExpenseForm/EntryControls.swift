import SwiftUI
import ExpenseCore

// MARK: - Образцы

/// Образец 46×60 в шите записи. У категории с подкатегориями внизу полоски двух ступеней оттенков
/// (макет `06-add`, `add.swatch.group.a11y`: трата пишется в категорию «без подкатегории»).
struct EntrySwatch: View {
    let choice: CategoryChoice
    let isSelected: Bool

    /// Полоски по макету `06-add`: зазор 1, ступень 1 — 5 pt, ступень 2 — 9 pt.
    private static let stripeHeights: [CGFloat] = [5, 9]

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CategorySwatch(iconName: choice.iconName, tone: choice.tone, isSelected: isSelected)
            .overlay(alignment: .bottom) {
                if choice.hasSubcategories, let tone = choice.tone {
                    stripes(tone)
                        // Подъём выбранного — как внутри `CategorySwatch`.
                        .offset(y: isSelected && !reduceMotion ? -Theme.Size.swatchLift : 0)
                        .motion(Motion.select, value: isSelected)
                }
            }
    }

    private func stripes(_ tone: GouacheTone) -> some View {
        VStack(spacing: 0) {
            ForEach(Self.stripeHeights.indices, id: \.self) { index in
                Theme.surface.frame(height: Theme.Spacing.subcategoryGap)
                tone.shade(index + 1).frame(height: Self.stripeHeights[index] * scale)
            }
        }
        .clipShape(UnevenRoundedRectangle(
            bottomLeadingRadius: Theme.Radius.swatch,
            bottomTrailingRadius: Theme.Radius.swatch,
            style: .continuous
        ))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Ряд «6 частых + Все». Не помещается (крупный текст) — в две строки, чтобы «Все» оставалась на виду;
/// не помещаются и они — прокручивается вбок.
struct EntrySwatchRow: View {
    let swatches: [CategoryChoice]
    let selectedID: UUID?
    let onSelect: (CategoryChoice) -> Void
    let onShowAll: () -> Void

    /// Колонок в двух строках: 6 частых + «Все» → 4 + 3.
    private static let wrappedColumns = 4

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            grid
            ScrollView(.horizontal) { row }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("add.swatches.a11y")
    }

    /// Колонки равной ширины: на ширине 358 шаг образцов 6 pt, как в макете; на широком экране — шире.
    private var row: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(swatches) { choice in
                swatchButton(choice)
            }
            allButton
        }
        .padding(.top, Theme.Size.swatchLift)
    }

    /// Две строки (крупный текст); зазор между ними — с запасом на подъём выбранного образца.
    private var grid: some View {
        let count = swatches.count + 1
        let columns = Self.wrappedColumns
        return Grid(horizontalSpacing: Theme.Spacing.xs, verticalSpacing: Theme.Size.swatchLift + Theme.Spacing.xs) {
            ForEach(Array(stride(from: 0, to: count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + columns, count), id: \.self) { index in
                        if swatches.indices.contains(index) {
                            swatchButton(swatches[index])
                        } else {
                            allButton
                        }
                    }
                }
            }
        }
        .padding(.top, Theme.Size.swatchLift)
    }

    private func swatchButton(_ choice: CategoryChoice) -> some View {
        let isSelected = choice.id == selectedID
        return Button { onSelect(choice) } label: {
            EntrySwatch(choice: choice, isSelected: isSelected)
        }
        .buttonStyle(.pressable())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(verbatim: choice.accessibilityName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Text(verbatim: choice.line)
        }
    }

    private var allButton: some View {
        Button(action: onShowAll) {
            AllCategoriesSwatch(title: "add.swatch.all")
        }
        .buttonStyle(.pressable())
        .frame(maxWidth: .infinity)
        .accessibilityLabel("add.swatch.all.a11y")
        .accessibilityShowsLargeContentViewer()
    }
}

// MARK: - Дата

/// Сегмент даты «Сегодня · Вчера · Дата…» (стекло-клавиша 44, пилюля как у сегмента периода).
/// «Дата…» открывает шит даты и после выбора показывает день («5 окт»); повторный тап — снова шит.
struct EntryDateSegment: View {
    enum Item: Hashable {
        case today, yesterday, other
    }

    let segment: EntryDate.Segment
    /// «5 окт» — для третьего пункта, когда выбран другой день.
    let pickedTitle: String?
    /// «Дата: понедельник, 5 октября».
    let pickedAccessibilityLabel: String?
    let onSelect: (Item) -> Void

    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            item(.today) { Text("add.date.today") }
            item(.yesterday) { Text("add.date.yesterday") }
            item(.other) {
                if let pickedTitle {
                    Text(verbatim: pickedTitle)
                } else {
                    Label("add.date.custom", systemImage: "calendar")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .frame(minHeight: Theme.Size.chip)
        .glass(.key)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("add.date.a11y")
    }

    private var selected: Item {
        switch segment {
        case .today: .today
        case .yesterday: .yesterday
        case .other: .other
        }
    }

    private func item(_ item: Item, @ViewBuilder label: () -> some View) -> some View {
        let isSelected = item == selected
        return Button {
            withAnimation(Motion.animation(Motion.segmentPill, reduceMotion: reduceMotion)) {
                onSelect(item)
            }
        } label: {
            label()
                .typeStyle(.callout)
                .foregroundStyle(isSelected ? Theme.ink : Theme.secondary)
                .lineLimit(1)
                .padding(.horizontal, Theme.Spacing.sm)
                .frame(minHeight: Theme.Size.segmentPill)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.segmentPill)
                            .paperShadow(Tokens.Shadow.segmentActive)
                            // При «Уменьшении движения» у каждого пункта своя пилюля: не едет, а проявляется.
                            .matchedGeometryEffect(id: reduceMotion ? AnyHashable(item) : AnyHashable("pill"), in: pillNamespace)
                    }
                }
                // Цель касания — вся высота капсулы 44, а не пилюля 36.
                .frame(minHeight: Theme.Size.chip)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
    }

    private func accessibilityLabel(_ item: Item) -> Text {
        switch item {
        case .today: Text("add.date.today")
        case .yesterday: Text("add.date.yesterday")
        case .other: pickedAccessibilityLabel.map { Text(verbatim: $0) } ?? Text("add.date.custom")
        }
    }
}

/// Шит «Дата траты»: системный календарь с tint графита. Будущие дни недоступны.
/// Выбор дня сразу закрывает шит.
struct EntryDateSheet: View {
    let onPick: (Date) -> Void

    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(date: Date, onPick: @escaping (Date) -> Void) {
        _date = State(initialValue: date)
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            DatePicker(selection: $date, in: ...Date.now, displayedComponents: .date) {
                Text("add.date.sheet")
            }
            .datePickerStyle(.graphical)
            .tint(Theme.ink)
            .padding(.horizontal, Theme.Spacing.screen)
            .frame(maxHeight: .infinity, alignment: .top)
            .sheetHeader("add.date.sheet", onClose: { dismiss() })
            .onChange(of: date) { _, newValue in onPick(newValue) }
        }
        .environment(\.locale, .app)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvasElevated)
    }
}

// MARK: - Быстрые суммы

/// Панель над системной цифровой клавиатурой: «+5 · +10 · +20 · +50 · +100», стекло-клавиши 44.
struct QuickAmountBar: View {
    let onAdd: (Int64) -> Void

    var body: some View {
        GlassEffectContainer(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(AmountInput.quickAmounts, id: \.self) { units in
                    Button { onAdd(units) } label: {
                        Text(verbatim: "+\(units)")
                            .typeStyle(.amountInline)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: Theme.Size.chip)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glass(.key)
                    .accessibilityLabel(Text(verbatim: L10n.format("add.quick.button.a11y", Int(units))))
                    .accessibilityShowsLargeContentViewer()
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("add.quick.a11y")
    }
}
