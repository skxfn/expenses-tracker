import SwiftUI
import ExpenseCore

// MARK: - Сегмент «Категория / Подкатегория»

/// Стеклянный сегмент уровня (макет `11-category`): как `GlassSegmentedControl`, но пункт может быть
/// неактивен — при 15 категориях «Категория», у категории с подкатегориями — «Подкатегория».
struct CategoryKindPicker: View {
    @Binding var selection: CategoryKind
    let isGroupEnabled: Bool
    let isSubcategoryEnabled: Bool

    @Namespace private var pillNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            segment(.group, title: "cat.type.group", isEnabled: isGroupEnabled)
            segment(.subcategory, title: "cat.type.sub", isEnabled: isSubcategoryEnabled)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .frame(minHeight: Theme.Size.segment)
        .glassEffect(.regular, in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .sensoryFeedback(Haptic.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("cat.type.a11y"))
    }

    private func segment(_ kind: CategoryKind, title: LocalizedStringKey, isEnabled: Bool) -> some View {
        let isSelected = selection == kind
        return Button {
            withAnimation(Motion.animation(Motion.segmentPill, reduceMotion: reduceMotion)) {
                selection = kind
            }
        } label: {
            Text(title)
                .typeStyle(.callout)
                .foregroundStyle(isSelected ? Theme.ink : (isEnabled ? Theme.secondary : Theme.tertiary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.segmentPill)
                .background {
                    if isSelected {
                        pill
                    }
                }
                // Цель касания — вся высота капсулы 44, а не только пилюля 36.
                .frame(minHeight: Theme.Size.segment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled && !isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer()
    }

    /// Активная пилюля едет к выбранному пункту; при Reduce Motion — не едет, а проявляется на месте
    /// (только прозрачность, §3.6).
    @ViewBuilder
    private var pill: some View {
        let capsule = Capsule()
            .fill(Theme.segmentPill)
            .paperShadow(Tokens.Shadow.segmentActive)
        if reduceMotion {
            capsule.transition(.opacity)
        } else {
            capsule.matchedGeometryEffect(id: "pill", in: pillNamespace)
        }
    }
}

// MARK: - Превью-«выкраска»

/// Превью категории — карточка-выкраска с окошком подписи и дыркой (макет `11-category`).
/// Карточка — цветом категории (у подкатегории — её ступень), окошко — лист с иконкой и названием.
struct CategoryChipPreview: View {
    let name: String
    let placeholder: LocalizedStringKey
    let iconName: String
    /// Цвет карточки.
    let fill: Color
    /// Иконка на листе окошка: deep в светлой, tint в тёмной.
    let iconColor: Color

    /// Размеры по макету: карточка 115×182, окошко 92×97, дырка 18, наклон −5°.
    private static let card = CGSize(width: 115, height: 182)
    private static let window = CGSize(width: 92, height: 97)
    private static let windowInset: CGFloat = 7.5
    private static let windowRadius: CGFloat = 4
    private static let holeDiameter: CGFloat = 18
    private static let holeBottom: CGFloat = 12
    private static let icon: CGFloat = 28
    private static let tilt = Angle.degrees(-5)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Spacing.sm) {
                CategoryIconImage(name: iconName)
                    .frame(width: Self.icon, height: Self.icon)
                    .foregroundStyle(iconColor)
                title
                    .typeStyle(.headline)
                    .multilineTextAlignment(.center)
                    // Одно слово не переносим (иначе «Назва-ние»), а уменьшаем; фразу — в две строки.
                    .lineLimit(isSingleWord ? 1 : 2)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(width: Self.window.width, height: Self.window.height)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Self.windowRadius, style: .continuous))
            .padding(.top, Self.windowInset)
            Spacer(minLength: 0)
            Circle()
                .fill(Theme.canvasElevated)
                .overlay { Circle().strokeBorder(Theme.separator, lineWidth: 1) }
                .frame(width: Self.holeDiameter, height: Self.holeDiameter)
                .padding(.bottom, Self.holeBottom)
        }
        .frame(width: Self.card.width, height: Self.card.height)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .paperShadow(Tokens.Shadow.segmentActive)
        .rotationEffect(Self.tilt)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityHidden(true)
    }

    /// Подсказка вместо пустого названия — одно короткое слово.
    private var isSingleWord: Bool {
        name.isEmpty || !name.contains(where: \.isWhitespace)
    }

    @ViewBuilder
    private var title: some View {
        if name.isEmpty {
            Text(placeholder).foregroundStyle(Theme.placeholder)
        } else {
            Text(verbatim: name).foregroundStyle(Theme.ink)
        }
    }
}

// MARK: - Ячейки цвета

/// Ряд или сетка ячеек цвета на листе (лесенка оттенков, 15 образцов «Гуаши»): ячейка 52, r 6, зазор 4.
private struct ColorCellsBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.swatch + Theme.Spacing.xs, style: .continuous)
        content
            .padding(Theme.Spacing.xs)
            .background(Theme.surface, in: shape)
            .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
    }
}

/// Ячейка цвета с подписью; выбранная — обводка ink 2 и зазор 2 внутри ячейки (макет `11-category`).
private struct ColorCell: View {
    let fill: Color
    let label: String?
    let labelColor: Color
    let isSelected: Bool
    /// Имена сестёр — SF 13/600 (макет), «занят: …» — SF 13 (§2.2).
    var labelStyle: TypeStyle = .footnoteStrong

    private static let ring: CGFloat = 2
    private static let gap: CGFloat = 2

    var body: some View {
        let inset = isSelected ? Self.ring + Self.gap : 0
        RoundedRectangle(cornerRadius: Theme.Radius.swatch - inset / 2, style: .continuous)
            .fill(fill)
            .overlay {
                if let label {
                    Text(verbatim: label)
                        .typeStyle(labelStyle)
                        .foregroundStyle(labelColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, Theme.Spacing.xs)
                }
            }
            .padding(inset)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.swatch + Self.gap, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: Self.ring)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.field)
            .motion(Motion.select, value: isSelected)
    }
}

// MARK: - Лесенка оттенков подкатегории

/// Пять ступеней тона категории: занятые подписаны именами сестёр, текущая обведена и подписана
/// названием подкатегории. Цвет не выбирается — показывает, какой оттенок достанется.
struct ShadeLadderView: View {
    let state: ShadeLadderState
    /// Название этой подкатегории (может быть пустым).
    let currentName: String
    let parentName: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<SubcategoryShades.stepCount, id: \.self) { step in
                let isCurrent = step == state.currentStep
                let names = state.names[step] + (isCurrent && !currentName.isEmpty ? [currentName] : [])
                ColorCell(
                    fill: state.tone.shade(step),
                    label: names.isEmpty ? nil : names.joined(separator: ", "),
                    labelColor: state.tone.labelOnShade(step),
                    isSelected: isCurrent
                )
            }
        }
        .modifier(ColorCellsBackground())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("cat.color.heading"))
        .accessibilityValue(Text(verbatim: accessibilityValue))
    }

    /// `cat.color.a11y` написана для одной занятой ступени; в остальных случаях — имена по порядку ступеней.
    private var accessibilityValue: String {
        let occupied = state.names.enumerated().filter { !$0.element.isEmpty }
        if occupied.count == 1, occupied[0].offset == 0, occupied[0].element.count == 1, state.currentStep == 1 {
            return L10n.format("cat.color.a11y", parentName, occupied[0].element[0])
        }
        var names = state.names
        if !currentName.isEmpty { names[state.currentStep].append(currentName) }
        return names.flatMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - 15 образцов «Гуаши»

/// Выбор тона категории: 15 образцов в порядке оттенка, 5 в ряд. Занятые другой категорией подписаны
/// «занят: Транспорт» (SF 13) и всё равно выбираются (§8 п. 12). Имена цветов — для VoiceOver.
struct ToneGridPicker: View {
    @Binding var selection: GouacheTone
    /// Занятые тоны и имя первой категории с ним.
    let occupied: [GouacheTone: String]

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs),
        count: SubcategoryShades.stepCount
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
            ForEach(GouacheTone.allCases, id: \.self) { tone in
                let taken = occupied[tone].map { L10n.format("cat.color.taken", $0) }
                Button {
                    selection = tone
                } label: {
                    ColorCell(
                        fill: tone.main,
                        label: taken,
                        labelColor: tone.labelOnMain,
                        isSelected: tone == selection,
                        labelStyle: .footnote
                    )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable())
                .accessibilityLabel(Text(LocalizedStringKey("cat.color.names." + tone.rawValue)))
                .accessibilityValue(Text(verbatim: taken ?? ""))
                .accessibilityAddTraits(tone == selection ? .isSelected : [])
            }
        }
        .modifier(ColorCellsBackground())
        .sensoryFeedback(Haptic.selection, trigger: selection)
    }
}

// MARK: - Иконки

/// Иконки категории: стеклянный поиск (по именам и синонимам, `CategoryIconSearch`) и группы по 6.
/// Выбранная — цветом категории (как карточка) с подписью-цветом иконки, поднята тенью.
struct IconGridPicker: View {
    @Binding var selection: String
    let selectedFill: Color
    let selectedIconColor: Color
    let shadowTone: GouacheTone

    @State private var query = ""
    @ScaledMetric(relativeTo: .body) private var iconSize = Theme.Size.swatchIcon

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 6)

    var body: some View {
        let groups = filteredGroups
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            searchField
            if groups.isEmpty {
                Text("cat.iconSearchEmpty")
                    .typeStyle(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            ForEach(groups, id: \.group.id) { entry in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(LocalizedStringKey(entry.group.titleKey))
                        .typeStyle(.footnoteStrong)
                        .foregroundStyle(Theme.secondary)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                        ForEach(entry.icons) { icon in
                            cell(icon)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(Haptic.selection, trigger: selection)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .typeStyle(.headline)
                .foregroundStyle(Theme.secondary)
                .accessibilityHidden(true)
            TextField(text: $query, prompt: Text("cat.icon.search.placeholder").foregroundStyle(Theme.placeholder)) {
                Text("cat.icon.search.a11y")
            }
            .typeStyle(.body)
            .foregroundStyle(Theme.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            // Подпись из `TextField(label:)` в дерево доступности не попадает — VoiceOver читал только пример.
            .accessibilityLabel(Text("cat.icon.search.a11y"))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(minHeight: Theme.Size.chip)
        .glass(.inContent)
    }

    private var filteredGroups: [(group: CategoryIconGroup, icons: [CategoryIcon])] {
        CategoryIconCatalog.groups.compactMap { group in
            let icons = CategoryIconSearch.visibleIcons(in: group, selection: selection)
                .filter { CategoryIconSearch.matches($0, query: query) }
            return icons.isEmpty ? nil : (group, icons)
        }
    }

    private func cell(_ icon: CategoryIcon) -> some View {
        let isSelected = icon.name == selection
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
        return Button {
            selection = icon.name
        } label: {
            shape
                .fill(isSelected ? selectedFill : Theme.surface)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    CategoryIconImage(name: icon.name)
                        .frame(width: iconSize, height: iconSize)
                        .foregroundStyle(isSelected ? selectedIconColor : Theme.secondary)
                }
                .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
                .modifier(SelectedLift(isSelected: isSelected, tone: shadowTone))
                .contentShape(shape)
        }
        .buttonStyle(.pressable(Motion.PressScale.circle))
        .accessibilityLabel(Text(verbatim: CategoryIconSearch.accessibilityName(of: icon) ?? ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Тень выбранного предмета цвета deep категории (`swatch-selected`), в тёмной — чёрная;
/// невыбранный — тень образца в покое.
private struct SelectedLift: ViewModifier {
    let isSelected: Bool
    let tone: GouacheTone
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if isSelected {
            let layers = Tokens.Shadow.swatchSelected
            content
                .shadow(color: color(layers[0]), radius: layers[0].blur / 2, x: layers[0].x, y: layers[0].y)
                .shadow(color: color(layers[1]), radius: layers[1].blur / 2, x: layers[1].x, y: layers[1].y)
        } else {
            content.paperShadow(Tokens.Shadow.swatchRest)
        }
    }

    private func color(_ layer: DeepShadowLayer) -> Color {
        colorScheme == .dark ? .black.opacity(layer.darkAlpha) : tone.deep.opacity(layer.lightAlpha)
    }
}

// MARK: - Поле и строка-переход

extension View {
    /// Поле редактора: лист r 14, высота 52, волосяной контур и тень образца в покое (DESIGN.md → Inputs).
    func paperField() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
        return padding(.horizontal, Theme.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.field, alignment: .leading)
            .background(Theme.surface, in: shape)
            .overlay { shape.strokeBorder(Theme.hairlineOutline, lineWidth: Theme.Size.hairline) }
            .paperShadow(Tokens.Shadow.swatchRest)
    }
}

/// Маленькая плашка категории (24 в строке «Категория ›», 28 в списке): заливка и иконка заданы снаружи.
struct MiniPlaque: View {
    let iconName: String
    let fill: Color
    let iconColor: Color
    var side: CGFloat = 24

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        RoundedRectangle(cornerRadius: side * scale / 4, style: .continuous)
            .fill(fill)
            .frame(width: side * scale, height: side * scale)
            .overlay {
                CategoryIconImage(name: iconName)
                    .frame(width: side * scale * 0.6, height: side * scale * 0.6)
                    .foregroundStyle(iconColor)
            }
            .accessibilityHidden(true)
    }
}
