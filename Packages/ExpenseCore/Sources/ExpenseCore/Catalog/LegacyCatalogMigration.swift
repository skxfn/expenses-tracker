import Foundation
import SwiftData

/// Перевод старых цветов, иконок и имён категорий на «Гуашь» и MingCute по `design/migration.json`.
/// Таблицы ниже — копия `colors`, `icons` и `defaultCategories` оттуда (сверяет `LegacyCatalogMigrationTests`).
/// Идемпотентно: старые и новые значения не пересекаются, уже новые значения не меняются.
public enum LegacyCatalogMigration {
    /// Переводит все категории контекста и сохраняет. Вызывается из стадии миграции V1 → V2.
    public static func apply(in context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
        for category in categories {
            let legacyDefault = legacyDefault(named: category.name)
            assign(colorHex(forLegacy: category.colorHex), to: \.colorHex, of: category)
            assign(iconName(forLegacy: category.iconName, categoryName: category.name), to: \.iconName, of: category)
            if let newName = legacyDefault?.template.name, isNameFree(newName, for: category, among: categories) {
                assign(newName, to: \.name, of: category)
            }
        }
        try context.save()
    }

    /// Цвет категории в «Гуаши» (`colorFallbackRule`): основной hex тона.
    public static func colorHex(forLegacy hex: String) -> String {
        tone(forLegacy: hex).mainHex
    }

    /// Тон для старого цвета: уже «Гуашь» → он же; таблица `colors`; иначе ближайший в OKLab.
    public static func tone(forLegacy hex: String) -> GouacheTone {
        if let tone = GouacheTone(mainHex: hex) { return tone }
        if let tone = colorTable[hex.uppercased()] { return tone }
        return nearestTone(to: hex)
    }

    /// Иконка MingCute для старого имени. У базовой категории, чью иконку не меняли, —
    /// иконка из `defaultCategories`; иначе таблица `icons`, иначе `iconFallback`.
    /// Имя, уже взятое из каталога MingCute, не меняется.
    public static func iconName(forLegacy name: String, categoryName: String) -> String {
        if CategoryIconCatalog.contains(name) { return name }
        if let legacyDefault = legacyDefault(named: categoryName), legacyDefault.oldIcon == name {
            return legacyDefault.template.iconName
        }
        return iconTable[name] ?? iconFallback
    }

    /// `iconFallback`: для имени SF Symbol не из таблицы.
    public static let iconFallback = "more-3-fill"

    // MARK: - Таблицы `design/migration.json`

    /// `colors`: старый hex (в верхнем регистре) → тон.
    static let colorTable: [String: GouacheTone] = [
        "#E5484D": .kinovar,
        "#DD6B20": .abrikos,
        "#B8860B": .okhra,
        "#789A2B": .olivka,
        "#2E9D63": .shalfey,
        "#109C8B": .viridon,
        "#0B93B8": .tseruleum,
        "#3E7BE6": .kobalt,
        "#5B5BD6": .ultramarin,
        "#8E4EC6": .ametist,
        "#D6409F": .pion,
        "#C2185B": .krapplak,
        "#A0674B": .umbra,
        "#5F7C8A": .slanets,
        "#8B8D98": .grafit
    ]

    /// `icons`: имя SF Symbol → имя MingCute.
    static let iconTable: [String: String] = [
        "cart.fill": "shopping-cart-1-fill",
        "basket.fill": "basket-fill",
        "bag.fill": "shopping-bag-1-fill",
        "fork.knife": "fork-knife-fill",
        "cup.and.saucer.fill": "teacup-fill",
        "takeoutbag.and.cup.and.straw.fill": "fries-fill",
        "wineglass.fill": "wineglass-fill",
        "birthday.cake.fill": "cake-fill",
        "car.fill": "car-fill",
        "bus.fill": "bus-fill",
        "tram.fill": "train-fill",
        "bicycle": "bike-fill",
        "fuelpump.fill": "gas-station-fill",
        "parkingsign.circle.fill": "parking-fill",
        "airplane": "airplane-fill",
        "suitcase.rolling.fill": "suitcase-fill",
        "house.fill": "home-4-fill",
        "sofa.fill": "sofa-fill",
        "lightbulb.fill": "bulb-fill",
        "bolt.fill": "bulb-fill",
        "drop.fill": "drop-fill",
        "flame.fill": "flame-fill",
        "washer.fill": "wash-machine-fill",
        "wrench.and.screwdriver.fill": "tool-fill",
        "wifi": "wifi-fill",
        "iphone": "cellphone-fill",
        "laptopcomputer": "laptop-fill",
        "tv.fill": "tv-1-fill",
        "headphones": "headphone-fill",
        "antenna.radiowaves.left.and.right": "signal-fill",
        "cross.case.fill": "first-aid-kit-fill",
        "pills.fill": "capsule-fill",
        "heart.fill": "heart-fill",
        "stethoscope": "stethoscope-fill",
        "dumbbell.fill": "barbell-fill",
        "figure.run": "run-fill",
        "leaf.fill": "leaf-fill",
        "theatermasks.fill": "celebrate-fill",
        "film.fill": "movie-fill",
        "music.note": "music-fill",
        "gamecontroller.fill": "game-2-fill",
        "ticket.fill": "ticket-fill",
        "book.fill": "book-2-fill",
        "paintpalette.fill": "palette-fill",
        "beach.umbrella.fill": "umbrella-2-fill",
        "tshirt.fill": "t-shirt-fill",
        "eyeglasses": "eyeglass-fill",
        "scissors": "scissors-fill",
        "comb.fill": "hair-fill",
        "sparkles": "sparkles-fill",
        "gift.fill": "gift-fill",
        "person.2.fill": "group-fill",
        "figure.and.child.holdinghands": "baby-carriage-fill",
        "teddybear.fill": "bear-fill",
        "pawprint.fill": "paw-fill",
        "graduationcap.fill": "mortarboard-fill",
        "creditcard.fill": "bank-card-fill",
        "banknote.fill": "cash-fill",
        "building.columns.fill": "bank-fill",
        "briefcase.fill": "briefcase-fill",
        "doc.text.fill": "bill-fill",
        "repeat.circle.fill": "repeat-fill",
        "tag.fill": "tag-fill",
        "ellipsis.circle.fill": "more-3-fill"
    ]

    /// Базовая категория прошлой версии и её новый шаблон (`defaultCategories`).
    struct LegacyDefault {
        let oldName: String
        let oldIcon: String
        let template: CategoryTemplate
    }

    /// `defaultCategories`: старые имя и иконка в порядке `DefaultCategories.all`.
    static let legacyDefaults: [LegacyDefault] = zip(
        [
            ("Продукты", "cart.fill"),
            ("Кафе и рестораны", "fork.knife"),
            ("Транспорт", "bus.fill"),
            ("Жильё и ЖКХ", "house.fill"),
            ("Связь и интернет", "wifi"),
            ("Здоровье", "cross.case.fill"),
            ("Развлечения", "theatermasks.fill"),
            ("Одежда", "tshirt.fill"),
            ("Подписки", "repeat.circle.fill"),
            ("Подарки", "gift.fill"),
            ("Образование", "graduationcap.fill"),
            ("Другое", "ellipsis.circle.fill")
        ],
        DefaultCategories.all
    ).map { LegacyDefault(oldName: $0.0, oldIcon: $0.1, template: $1) }

    // MARK: - Внутреннее

    /// `defaultCategoriesRule`: базовая категория узнаётся по старому имени (после trim, без учёта регистра).
    static func legacyDefault(named name: String) -> LegacyDefault? {
        let key = comparable(name)
        return legacyDefaults.first { comparable($0.oldName) == key }
    }

    /// Новое имя не занято другой категорией (с учётом уже переименованных в этом проходе).
    private static func isNameFree(_ name: String, for category: ExpenseCategory, among all: [ExpenseCategory]) -> Bool {
        let key = comparable(name)
        return !all.contains { $0.id != category.id && comparable($0.name) == key }
    }

    private static func comparable(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Пишет только изменившееся значение: повторный проход не помечает модели изменёнными.
    private static func assign(_ value: String, to keyPath: ReferenceWritableKeyPath<ExpenseCategory, String>, of category: ExpenseCategory) {
        if category[keyPath: keyPath] != value {
            category[keyPath: keyPath] = value
        }
    }

    /// `colorFallbackRule`: цветность OKLCH C < 0,03 или невалидный hex — Графит;
    /// иначе тон с минимальным √(Δa²+Δb²) в OKLab среди тонов без Графита.
    static func nearestTone(to hex: String) -> GouacheTone {
        guard let color = OKLab(hex: hex), color.chroma >= 0.03 else { return .grafit }
        return chromaticTones.min { color.abDistance(to: $0.color) < color.abDistance(to: $1.color) }?.tone ?? .grafit
    }

    private static let chromaticTones: [(tone: GouacheTone, color: OKLab)] = GouacheTone.allCases
        .filter { $0 != .grafit }
        .compactMap { tone in OKLab(hex: tone.mainHex).map { (tone, $0) } }
}

/// Цвет в OKLab (Björn Ottosson): нужен только правилу ближайшего тона.
struct OKLab {
    let lightness: Double
    let a: Double
    let b: Double

    init?(hex: String) {
        guard let rgb = HexColor.components(hex) else { return nil }
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let (red, green, blue) = (linear(rgb.red), linear(rgb.green), linear(rgb.blue))
        let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
        let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
        let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
        lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    /// Цветность OKLCH.
    var chroma: Double { (a * a + b * b).squareRoot() }

    /// Расстояние в плоскости a/b (без светлоты).
    func abDistance(to other: OKLab) -> Double {
        ((a - other.a) * (a - other.a) + (b - other.b) * (b - other.b)).squareRoot()
    }
}
