// Сгенерировано scripts/gen_tokens.py из .impeccable/design.json и DESIGN.md. Руками не править:
// после правки источников — python3 scripts/gen_tokens.py.

import CoreGraphics
import ExpenseCore

/// Пара значений «свет / ночь» в формате `0xRRGGBB`.
nonisolated struct TokenPair: Sendable, Hashable {
    let light: UInt32
    let dark: UInt32
}

/// Значения тона «Гуаши» (`0xRRGGBB`). Роли и выбор по теме — в `Gouache+Colors.swift`.
nonisolated struct GouacheTokens: Sendable, Hashable {
    /// Основной тон в светлой теме (он же хранится в данных).
    let main: UInt32
    /// Основной тон в тёмной теме (отличается только у Пиона — pion-night).
    let mainNight: UInt32
    let tint: UInt32
    let deep: UInt32
    let darktint: UInt32
    /// Подпись на основном тоне: графит или бумага; в тёмной теме не инвертируется.
    let labelOnMain: UInt32
    /// Светлые ступени подкатегорий (`subcategoryShades`; первая — основной тон).
    let shadesLight: [UInt32]
    /// Тёмные ступени подкатегорий (`subcategoryShadesDark`; первая — основной ночной тон).
    let shadesDark: [UInt32]
    /// Подписи на светлых ступенях: на первой — labelOnMain, дальше deep или бумага по контрасту.
    let labelsLight: [UInt32]
    /// Подписи на тёмных ступенях: на первой — labelOnMain, дальше night-ink.
    let labelsDark: [UInt32]
}

/// Тень бумажного предмета: в светлой — тёплая `rgb` с `lightAlpha`, в тёмной — чёрная с `darkAlpha`
/// (design.json → shadows → dark-rule). `blur` — как в CSS, радиус SwiftUI ≈ blur / 2.
nonisolated struct ShadowToken: Sendable, Hashable {
    let x: CGFloat
    let y: CGFloat
    let blur: CGFloat
    let rgb: UInt32
    let lightAlpha: Double
    let darkAlpha: Double
}

/// Слой тени цвета deep (выбранный образец); в тёмной теме — чёрный с тем же правилом альфы.
nonisolated struct DeepShadowLayer: Sendable, Hashable {
    let x: CGFloat
    let y: CGFloat
    let blur: CGFloat
    let lightAlpha: Double
    let darkAlpha: Double
}

/// Шрифтовой токен DESIGN.md → typography: кегль, начертание, трекинг в em, табличные цифры.
nonisolated struct TypeScaleToken: Sendable, Hashable {
    let size: CGFloat
    let weight: Int
    let trackingEm: CGFloat
    let tabularDigits: Bool
}

nonisolated enum Tokens {
    /// Нейтрали и семантика (свет / ночь).
    enum Neutral {
        /// Фон экрана.
        static let canvas = TokenPair(light: 0xF3F0EA, dark: 0x13110F)
        /// Фон шита.
        static let canvasElevated = TokenPair(light: 0xF3F0EA, dark: 0x181513)
        /// Лист, группы, поля, карточки (и в шитах).
        static let surface = TokenPair(light: 0xFDFBF7, dark: 0x1E1B18)
        /// Текст, главное действие, фокус.
        static let ink = TokenPair(light: 0x221D18, dark: 0xEFECE7)
        /// Подписи, «Br», неактивные сегменты.
        static let secondary = TokenPair(light: 0x5F5A54, dark: 0xB7B4AE)
        /// Только неактивное и будущее.
        static let tertiary = TokenPair(light: 0x7F7B75, dark: 0x898680)
        /// Плейсхолдер на стекле.
        static let placeholder = TokenPair(light: 0x6B665F, dark: 0x96928B)
        /// Шевроны, контур чекбокса, прошлые столбики (≥ 3:1).
        static let graphic = TokenPair(light: 0x8A857E, dark: 0x78726C)
        /// Волосяные линии 0,5, контур «Все».
        static let separator = TokenPair(light: 0xDBD7D0, dark: 0x35322F)
        /// Текст и иконка «Удалить».
        static let destructive = TokenPair(light: 0xB3261E, dark: 0xEA6C5C)
        /// Текст и иконка на главном действии.
        static let onInk = TokenPair(light: 0xFDFBF7, dark: 0x1E1B18)
        /// Выглядывающий родительский шит (если рисуем сами).
        static let sheetBehind = TokenPair(light: 0x8E8A84, dark: 0x252220)
    }

    /// Неизменяемые бумага и графит: подписи и иконки на основных тонах «Гуаши» не инвертируются.
    enum Paper {
        static let surface: UInt32 = 0xFDFBF7
        static let graphite: UInt32 = 0x221D18
    }

    /// Шкала графита heat-0…4 (календарь, тепловая карта, «Привычки»).
    static let heat: [TokenPair] = [
        TokenPair(light: 0xFDFBF7, dark: 0x1E1B18),
        TokenPair(light: 0xE6E0DA, dark: 0x352F29),
        TokenPair(light: 0xCAC3BB, dark: 0x4D4740),
        TokenPair(light: 0x9F978F, dark: 0x68625B),
        TokenPair(light: 0x4E4640, dark: 0xC3BCB6),
    ]

    /// Радиусы (DESIGN.md → rounded), pt.
    enum Radius {
        static let chipInner: CGFloat = 2
        static let swatch: CGFloat = 6
        static let tile: CGFloat = 7
        static let plaque: CGFloat = 10
        static let lens: CGFloat = 12
        static let field: CGFloat = 14
        static let key: CGFloat = 13
        static let group: CGFloat = 22
        static let sheetPanel: CGFloat = 28
        static let sheet: CGFloat = 38
    }

    /// Отступы (DESIGN.md → spacing), pt.
    enum Spacing {
        static let hairline: CGFloat = 2
        static let tileGap: CGFloat = 3
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let tabbarBottom: CGFloat = 30
        static let headerTop: CGFloat = 56
    }

    /// Размеры компонентов (DESIGN.md → components), pt.
    enum Size {
        static let buttonProminentHeight: CGFloat = 50
        static let buttonProminentNightHeight: CGFloat = 50
        static let buttonGlassHeight: CGFloat = 50
        static let buttonGlassDestructiveHeight: CGFloat = 50
        static let iconButtonGlass: CGFloat = 44
        static let segmentPeriodHeight: CGFloat = 44
        static let segmentPeriodActiveHeight: CGFloat = 36
        static let tabBarHeight: CGFloat = 62
        static let tabBarAdd: CGFloat = 62
        static let dayHeaderHeight: CGFloat = 36
        static let feedRowHeight: CGFloat = 60
        static let categoryPlaque: CGFloat = 36
        static let swatchChipWidth: CGFloat = 46
        static let swatchChipHeight: CGFloat = 60
        static let swatchChipSelectedWidth: CGFloat = 46
        static let swatchChipSelectedHeight: CGFloat = 60
        static let quickSumChipHeight: CGFloat = 44
        static let stripRowHeight: CGFloat = 56
        static let calendarCellHeight: CGFloat = 52
        static let textFieldHeight: CGFloat = 52
    }

    /// Шкала шрифтов (DESIGN.md → typography).
    enum TypeScale {
        static let amountDisplay = TypeScaleToken(size: 60, weight: 500, trackingEm: -0.02, tabularDigits: true)
        static let amountTotal = TypeScaleToken(size: 40, weight: 500, trackingEm: -0.02, tabularDigits: true)
        static let monthTitle = TypeScaleToken(size: 28, weight: 600, trackingEm: -0.01, tabularDigits: false)
        static let rangeDays = TypeScaleToken(size: 22, weight: 600, trackingEm: -0.01, tabularDigits: true)
        static let rangeMonth = TypeScaleToken(size: 17, weight: 500, trackingEm: 0, tabularDigits: false)
        static let amountInline = TypeScaleToken(size: 15, weight: 500, trackingEm: 0, tabularDigits: true)
        static let largeTitle = TypeScaleToken(size: 34, weight: 700, trackingEm: 0, tabularDigits: false)
        static let title = TypeScaleToken(size: 22, weight: 600, trackingEm: 0, tabularDigits: false)
        static let headline = TypeScaleToken(size: 17, weight: 600, trackingEm: 0, tabularDigits: false)
        static let body = TypeScaleToken(size: 17, weight: 400, trackingEm: 0, tabularDigits: false)
        static let callout = TypeScaleToken(size: 15, weight: 600, trackingEm: 0, tabularDigits: false)
        static let footnote = TypeScaleToken(size: 13, weight: 400, trackingEm: 0, tabularDigits: false)
        static let caption = TypeScaleToken(size: 11, weight: 600, trackingEm: 0, tabularDigits: false)
    }

    /// Тени бумажных предметов (стекло рисует свои тени само).
    enum Shadow {
        static let sheet = ShadowToken(x: 0, y: -6, blur: 24, rgb: 0x221D18, lightAlpha: 0.06, darkAlpha: 0.298)
        static let swatchRest = ShadowToken(x: 0, y: 1, blur: 2, rgb: 0x221D18, lightAlpha: 0.06, darkAlpha: 0.298)
        static let segmentActive = ShadowToken(x: 0, y: 2, blur: 8, rgb: 0x1E1914, lightAlpha: 0.12, darkAlpha: 0.376)
        /// Выбранный образец: два слоя цвета deep категории.
        static let swatchSelected: [DeepShadowLayer] = [
            DeepShadowLayer(x: 0, y: 8, blur: 14, lightAlpha: 0.26, darkAlpha: 0.55),
            DeepShadowLayer(x: 0, y: 2, blur: 4, lightAlpha: 0.18, darkAlpha: 0.454),
        ]
    }
}

extension GouacheTone {
    /// Значения тона из design.json.
    nonisolated var tokens: GouacheTokens {
        switch self {
        case .krapplak: // Краплак
            GouacheTokens(
                main: 0xCE6C8D, mainNight: 0xCE6C8D,
                tint: 0xFFE0E8, deep: 0x7D2C4B, darktint: 0x46202D,
                labelOnMain: 0x221D18,
                shadesLight: [0xCE6C8D, 0xE98BA9, 0xFFADC6],
                shadesDark: [0xCE6C8D, 0xA14B69, 0x8C3F5A, 0x77324B, 0x63263D],
                labelsLight: [0x221D18, 0x7D2C4B, 0x7D2C4B],
                labelsDark: [0x221D18, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .kinovar: // Киноварь
            GouacheTokens(
                main: 0xD16E5A, mainNight: 0xD16E5A,
                tint: 0xFFE2DC, deep: 0x802F20, darktint: 0x47211A,
                labelOnMain: 0x221D18,
                shadesLight: [0xD16E5A, 0xEC8D79, 0xFFB09F],
                shadesDark: [0xD16E5A, 0xA54E3D, 0x8F4132, 0x7A3427, 0x66281C],
                labelsLight: [0x221D18, 0x802F20, 0x802F20],
                labelsDark: [0x221D18, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .abrikos: // Абрикос
            GouacheTokens(
                main: 0xBE7C30, mainNight: 0xBE7C30,
                tint: 0xFDE5CE, deep: 0x6F4101, darktint: 0x422707,
                labelOnMain: 0x221D18,
                shadesLight: [0xBE7C30, 0xD89957, 0xF3B77A],
                shadesDark: [0xBE7C30, 0x945A0C, 0x804C02, 0x6B3E00, 0x573200],
                labelsLight: [0x221D18, 0x6F4101, 0x6F4101],
                labelsDark: [0x221D18, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .okhra: // Охра
            GouacheTokens(
                main: 0x967729, mainNight: 0x967729,
                tint: 0xF5E8CC, deep: 0x614901, darktint: 0x3B2B01,
                labelOnMain: 0xFDFBF7,
                shadesLight: [0x967729, 0xB0934E, 0xCBAF70],
                shadesDark: [0x967729, 0x7F641C, 0x6D5412, 0x5C4607, 0x4B3800],
                labelsLight: [0xFDFBF7, 0x614901, 0x614901],
                labelsDark: [0xFDFBF7, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .olivka: // Оливка
            GouacheTokens(
                main: 0x759242, mainNight: 0x759242,
                tint: 0xE3EED4, deep: 0x3F5609, darktint: 0x26330E,
                labelOnMain: 0x221D18,
                shadesLight: [0x759242, 0x91AD63, 0xAEC984],
                shadesDark: [0x759242, 0x566F26, 0x485F1D, 0x3B4F12, 0x2E3F07],
                labelsLight: [0x221D18, 0x3F5609, 0x3F5609],
                labelsDark: [0x221D18, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .shalfey: // Шалфей
            GouacheTokens(
                main: 0x3E9B6B, mainNight: 0x3E9B6B,
                tint: 0xD4F2DF, deep: 0x005D37, darktint: 0x0C3722,
                labelOnMain: 0x221D18,
                shadesLight: [0x3E9B6B, 0x63B688, 0x85D2A5],
                shadesDark: [0x3E9B6B, 0x1D764C, 0x12643F, 0x055432, 0x004327],
                labelsLight: [0x221D18, 0x005D37, 0x005D37],
                labelsDark: [0x221D18, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .viridon: // Виридон
            GouacheTokens(
                main: 0x308F8E, mainNight: 0x308F8E,
                tint: 0xD5F0EF, deep: 0x005A5A, darktint: 0x003635,
                labelOnMain: 0x221D18,
                shadesLight: [0x308F8E, 0x57AAA9, 0x7BC5C4],
                shadesDark: [0x308F8E, 0x177271, 0x0C6161, 0x025150, 0x014040],
                labelsLight: [0x221D18, 0x005A5A, 0x005A5A],
                labelsDark: [0x221D18, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .tseruleum: // Церулеум
            GouacheTokens(
                main: 0x277594, mainNight: 0x277594,
                tint: 0xD0EFFF, deep: 0x08556F, darktint: 0x003345,
                labelOnMain: 0xFDFBF7,
                shadesLight: [0x277594, 0x4C90AD, 0x6DABC7],
                shadesDark: [0x277594, 0x1D6480, 0x12546D, 0x06455B, 0x013548],
                labelsLight: [0xFDFBF7, 0xFDFBF7, 0x08556F],
                labelsDark: [0xFDFBF7, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .kobalt: // Кобальт
            GouacheTokens(
                main: 0x4569B4, mainNight: 0x4569B4,
                tint: 0xDFEAFE, deep: 0x2C4A8A, darktint: 0x1E2D4C,
                labelOnMain: 0xFDFBF7,
                shadesLight: [0x4569B4, 0x6185CD, 0x7FA1E5],
                shadesDark: [0x4569B4, 0x395A9D, 0x2E4B87, 0x233C71, 0x182E5D],
                labelsLight: [0xFDFBF7, 0xFDFBF7, 0x2C4A8A],
                labelsDark: [0xFDFBF7, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .ultramarin: // Ультрамарин
            GouacheTokens(
                main: 0x7585D9, mainNight: 0x7585D9,
                tint: 0xE3E9FF, deep: 0x3B458A, darktint: 0x252B4C,
                labelOnMain: 0x221D18,
                shadesLight: [0x7585D9, 0x91A2F2, 0xB2C1FF],
                shadesDark: [0x7585D9, 0x5562AC, 0x485395, 0x3B447F, 0x2E366B],
                labelsLight: [0x221D18, 0x3B458A, 0x3B458A],
                labelsDark: [0x221D18, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .ametist: // Аметист
            GouacheTokens(
                main: 0xA978C1, mainNight: 0xA978C1,
                tint: 0xF4E2FD, deep: 0x623975, darktint: 0x392443,
                labelOnMain: 0x221D18,
                shadesLight: [0xA978C1, 0xC495DB, 0xDFB3F5],
                shadesDark: [0xA978C1, 0x825697, 0x704982, 0x5E3C6F, 0x4E2F5C],
                labelsLight: [0x221D18, 0x623975, 0x623975],
                labelsDark: [0x221D18, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .pion: // Пион
            GouacheTokens(
                main: 0x9A4C7C, mainNight: 0x9F5181,
                tint: 0xFEDFF0, deep: 0x74315B, darktint: 0x422135,
                labelOnMain: 0xFDFBF7,
                shadesLight: [0x9A4C7C, 0xB46996, 0xCF87B1],
                shadesDark: [0x9F5181, 0x8A4470, 0x76385F, 0x632B4E, 0x511F3F],
                labelsLight: [0xFDFBF7, 0xFDFBF7, 0x74315B],
                labelsDark: [0xFDFBF7, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .umbra: // Умбра
            GouacheTokens(
                main: 0x886248, mainNight: 0x886248,
                tint: 0xFFE4D2, deep: 0x65452E, darktint: 0x44250C,
                labelOnMain: 0xFDFBF7,
                shadesLight: [0x886248, 0xA27D64, 0xBC9981],
                shadesDark: [0x886248, 0x75533C, 0x634530, 0x523725, 0x422A19],
                labelsLight: [0xFDFBF7, 0xFDFBF7, 0x65452E],
                labelsDark: [0xFDFBF7, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .slanets: // Сланец
            GouacheTokens(
                main: 0x798DA3, mainNight: 0x798DA3,
                tint: 0xE3EAF2, deep: 0x3E4F61, darktint: 0x1E2F42,
                labelOnMain: 0x221D18,
                shadesLight: [0x798DA3, 0x95A8BE, 0xB3C5D9],
                shadesDark: [0x798DA3, 0x57697C, 0x49596A, 0x3C4A59, 0x2F3B49],
                labelsLight: [0x221D18, 0x3E4F61, 0x3E4F61],
                labelsDark: [0x221D18, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        case .grafit: // Графит
            GouacheTokens(
                main: 0x797875, mainNight: 0x797875,
                tint: 0xEAE9E6, deep: 0x4E4D4A, darktint: 0x2F2E2B,
                labelOnMain: 0xFDFBF7,
                shadesLight: [0x797875, 0x949390, 0xAFAFAC],
                shadesDark: [0x797875, 0x686764, 0x585755, 0x494846, 0x3A3A38],
                labelsLight: [0xFDFBF7, 0xFDFBF7, 0x4E4D4A],
                labelsDark: [0xFDFBF7, 0xEFECE7, 0xEFECE7, 0xEFECE7, 0xEFECE7]
            )
        }
    }
}
