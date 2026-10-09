#!/usr/bin/env python3
"""Генерирует App/Shared/Theme/Tokens.generated.swift из `.impeccable/design.json` и YAML-шапки DESIGN.md.

Источники (design/INTEGRATION.md §1, §3.2): цвета — `design.json` (colorMeta, darkTheme), при расхождении
с DESIGN.md прав design.json (расхождения печатаются предупреждением). Радиусы, отступы, размеры компонентов
и шкала шрифтов есть только в DESIGN.md. Только stdlib.

Запуск из корня репозитория: python3 scripts/gen_tokens.py [--check]
--check — не писать файл, а упасть, если сгенерированный текст отличается от лежащего в репозитории.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESIGN_JSON = ROOT / ".impeccable" / "design.json"
DESIGN_MD = ROOT / "DESIGN.md"
OUTPUT = ROOT / "App" / "Shared" / "Theme" / "Tokens.generated.swift"

HEX = re.compile(r"#[0-9A-Fa-f]{6}")


def fail(message):
    sys.exit(f"gen_tokens: {message}")


def hex_value(text, where):
    match = HEX.fullmatch(text.strip()) if isinstance(text, str) else None
    if not match:
        fail(f"{where}: ожидался #RRGGBB, получено {text!r}")
    return "0x" + match.group(0)[1:].upper()


def camel(name):
    head, *rest = name.split("-")
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


# --- YAML-шапка DESIGN.md: только нужное подмножество (вложенные словари, скалярные значения) ---

def parse_front_matter(text):
    lines = text.split("\n")
    if lines[0].strip() != "---":
        fail("DESIGN.md: нет YAML-шапки")
    end = lines.index("---", 1)
    root, stack = {}, [(-1, None)]
    stack[0] = (-1, root)
    for raw in lines[1:end]:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        key, _, value = raw.strip().partition(":")
        value = value.strip()
        while stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1]
        if value:
            parent[key] = value.strip('"')
        else:
            parent[key] = {}
            stack.append((indent, parent[key]))
    return root


def px(value, where):
    match = re.fullmatch(r"(-?\d+(?:\.\d+)?)px", value)
    if not match:
        fail(f"{where}: ожидались px, получено {value!r}")
    return float(match.group(1))


def number(value):
    return f"{value:g}"


# --- Сбор значений ---

def light_from_role(meta, name):
    """Светлое значение служебных нейтралей лежит только в тексте роли: «…; light: #6B665F»."""
    match = re.search(r"light:\s*(#[0-9A-Fa-f]{6})", meta[name]["role"])
    if not match:
        fail(f"darkTheme.neutrals.{name}: в role нет «light: #RRGGBB»")
    return hex_value(match.group(1), f"{name}.role")


def neutrals(ext):
    meta = ext["colorMeta"]
    dark = ext["darkTheme"]["neutrals"]
    semantic = ext["darkTheme"]["semantic"]

    def canonical(name):
        return hex_value(meta[name]["canonical"], f"colorMeta.{name}")

    def night(name):
        return hex_value(dark[name]["hex"], f"darkTheme.neutrals.{name}")

    return [
        ("canvas", "фон экрана", canonical("paper-canvas"), night("night-canvas")),
        ("canvasElevated", "фон шита", light_from_role(dark, "night-canvas-elevated"), night("night-canvas-elevated")),
        ("surface", "лист, группы, поля, карточки (и в шитах)", canonical("paper-surface"), night("night-surface")),
        ("ink", "текст, главное действие, фокус", canonical("graphite"), night("night-ink")),
        ("secondary", "подписи, «Br», неактивные сегменты", canonical("graphite-secondary"), night("night-secondary")),
        ("tertiary", "только неактивное и будущее", canonical("graphite-tertiary"), night("night-tertiary")),
        ("placeholder", "плейсхолдер на стекле", light_from_role(dark, "night-placeholder"), night("night-placeholder")),
        ("graphic", "шевроны, контур чекбокса, прошлые столбики (≥ 3:1)", light_from_role(dark, "night-graphic"), night("night-graphic")),
        ("separator", "волосяные линии 0,5, контур «Все»", canonical("paper-separator"), night("night-separator")),
        ("destructive", "текст и иконка «Удалить»", canonical("destructive"),
         hex_value(semantic["night-destructive"]["hex"], "darkTheme.semantic.night-destructive")),
        ("onInk", "текст и иконка на главном действии", light_from_role(dark, "night-on-ink"), night("night-on-ink")),
        ("sheetBehind", "выглядывающий родительский шит (если рисуем сами)", light_from_role(dark, "night-sheet-behind"), night("night-sheet-behind")),
    ]


def gouache(ext, yaml_colors):
    meta = ext["colorMeta"]
    dark = ext["darkTheme"]["gouache"]
    tones = []
    for tone, night in dark.items():
        def canonical(suffix):
            key = tone + suffix
            value = hex_value(meta[key]["canonical"], f"colorMeta.{key}")
            yaml_value = yaml_colors.get(key)
            if yaml_value and hex_value(yaml_value, f"DESIGN.md colors.{key}") != value:
                print(f"предупреждение: {key}: DESIGN.md {yaml_value} ≠ design.json {value}, взят design.json")
            return value

        main = canonical("")
        darktint = canonical("-darktint")
        if hex_value(night["darktint"], f"darkTheme.gouache.{tone}.darktint") != darktint:
            fail(f"{tone}: darktint в colorMeta и darkTheme.gouache расходятся")
        shades_light = [hex_value(v, f"{tone}.subcategoryShades") for v in meta[tone]["subcategoryShades"]]
        shades_dark = [hex_value(v, f"{tone}.subcategoryShadesDark") for v in meta[tone]["subcategoryShadesDark"]]
        steps_dark = [hex_value(v, f"darkTheme.gouache.{tone}.stepsDark") for v in night["stepsDark"]]
        if shades_dark != steps_dark:
            fail(f"{tone}: subcategoryShadesDark и darkTheme.stepsDark расходятся")
        if shades_light[0] != main:
            fail(f"{tone}: первая светлая ступень должна быть основным тоном")
        label_on_main = hex_value(night["labelOnMain"], f"darkTheme.gouache.{tone}.labelOnMain")
        deep = canonical("-deep")
        paper = hex_value(meta["paper-surface"]["canonical"], "colorMeta.paper-surface")
        ink_on_dark = hex_value(night["labelOnStepsDark"], f"darkTheme.gouache.{tone}.labelOnStepsDark")
        tones.append({
            "id": tone,
            "name": night["name"],
            "main": main,
            "mainNight": hex_value(night["main"], f"darkTheme.gouache.{tone}.main"),
            "tint": canonical("-tint"),
            "deep": deep,
            "darktint": darktint,
            "labelOnMain": label_on_main,
            "labelsLight": labels_on_shades(shades_light, label_on_main, [deep, paper]),
            "labelsDark": labels_on_shades(shades_dark, label_on_main, [ink_on_dark]),
            "shadesLight": shades_light,
            "shadesDark": shades_dark,
        })
    if len(tones) != 15:
        fail(f"ожидалось 15 тонов «Гуаши», найдено {len(tones)}")
    return tones


SHADOW = re.compile(r"(-?[\d.]+)(?:px)?\s+(-?[\d.]+)px\s+([\d.]+)px\s+rgba\((\d+),(\d+),(\d+),([\d.]+)\)")
DEEP_SHADOW = re.compile(r"(-?[\d.]+)\s+(-?[\d.]+)px\s+([\d.]+)px\s+<deep>/([\d.]+)")


def luminance(value):
    """Относительная яркость WCAG для `0xRRGGBB`."""
    rgb = int(value, 16)
    channels = [((rgb >> shift) & 0xFF) / 255 for shift in (16, 8, 0)]
    linear = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(a, b):
    la, lb = sorted([luminance(a), luminance(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)


def labels_on_shades(shades, label_on_main, candidates):
    """Ступень 1 — основной тон: подпись labelOnMain (не инвертируется). Остальные — кандидат с большим
    контрастом. Так нарисована доска «Тёмная тема: палитра» (у Кобальта и Пиона на 2-й светлой ступени — бумага)."""
    return [label_on_main] + [max(candidates, key=lambda c: contrast(c, shade)) for shade in shades[1:]]


def dark_alpha(alpha):
    # design.json → shadows → dark-rule: α = min(0,55; 0,22 + 1,3·α светлой).
    return min(0.55, 0.22 + 1.3 * alpha)


def shadows(ext):
    by_name = {item["name"]: item["value"] for item in ext["shadows"]}
    result = []
    for name in ["sheet", "swatch-rest", "segment-active"]:
        value = by_name[name]
        layers = [m for m in SHADOW.finditer(value) if "inset" not in value[max(0, m.start() - 6):m.start()]]
        if not layers:
            fail(f"shadows.{name}: не разобрать {value!r}")
        x, y, blur, r, g, b, alpha = layers[-1].groups()
        rgb = "0x%02X%02X%02X" % (int(r), int(g), int(b))
        result.append((camel(name), float(x), float(y), float(blur), rgb, float(alpha), dark_alpha(float(alpha))))
    deep_layers = [m.groups() for m in DEEP_SHADOW.finditer(by_name["swatch-selected"])]
    if len(deep_layers) != 2:
        fail("shadows.swatch-selected: ожидались два слоя <deep>/α")
    return result, [(float(x), float(y), float(blur), float(a)) for x, y, blur, a in deep_layers]


# --- Swift ---

def swift_pair(light, dark):
    return f"TokenPair(light: {light}, dark: {dark})"


def swift_list(values):
    return "[" + ", ".join(values) + "]"


def render(ext, yaml):
    out = [
        "// Сгенерировано scripts/gen_tokens.py из .impeccable/design.json и DESIGN.md. Руками не править:",
        "// после правки источников — python3 scripts/gen_tokens.py.",
        "",
        "import CoreGraphics",
        "import ExpenseCore",
        "",
        "/// Пара значений «свет / ночь» в формате `0xRRGGBB`.",
        "nonisolated struct TokenPair: Sendable, Hashable {",
        "    let light: UInt32",
        "    let dark: UInt32",
        "}",
        "",
        "/// Значения тона «Гуаши» (`0xRRGGBB`). Роли и выбор по теме — в `Gouache+Colors.swift`.",
        "nonisolated struct GouacheTokens: Sendable, Hashable {",
        "    /// Основной тон в светлой теме (он же хранится в данных).",
        "    let main: UInt32",
        "    /// Основной тон в тёмной теме (отличается только у Пиона — pion-night).",
        "    let mainNight: UInt32",
        "    let tint: UInt32",
        "    let deep: UInt32",
        "    let darktint: UInt32",
        "    /// Подпись на основном тоне: графит или бумага; в тёмной теме не инвертируется.",
        "    let labelOnMain: UInt32",
        "    /// Светлые ступени подкатегорий (`subcategoryShades`; первая — основной тон).",
        "    let shadesLight: [UInt32]",
        "    /// Тёмные ступени подкатегорий (`subcategoryShadesDark`; первая — основной ночной тон).",
        "    let shadesDark: [UInt32]",
        "    /// Подписи на светлых ступенях: на первой — labelOnMain, дальше deep или бумага по контрасту.",
        "    let labelsLight: [UInt32]",
        "    /// Подписи на тёмных ступенях: на первой — labelOnMain, дальше night-ink.",
        "    let labelsDark: [UInt32]",
        "}",
        "",
        "/// Тень бумажного предмета: в светлой — тёплая `rgb` с `lightAlpha`, в тёмной — чёрная с `darkAlpha`",
        "/// (design.json → shadows → dark-rule). `blur` — как в CSS, радиус SwiftUI ≈ blur / 2.",
        "nonisolated struct ShadowToken: Sendable, Hashable {",
        "    let x: CGFloat",
        "    let y: CGFloat",
        "    let blur: CGFloat",
        "    let rgb: UInt32",
        "    let lightAlpha: Double",
        "    let darkAlpha: Double",
        "}",
        "",
        "/// Слой тени цвета deep (выбранный образец); в тёмной теме — чёрный с тем же правилом альфы.",
        "nonisolated struct DeepShadowLayer: Sendable, Hashable {",
        "    let x: CGFloat",
        "    let y: CGFloat",
        "    let blur: CGFloat",
        "    let lightAlpha: Double",
        "    let darkAlpha: Double",
        "}",
        "",
        "/// Шрифтовой токен DESIGN.md → typography: кегль, начертание, трекинг в em, табличные цифры.",
        "nonisolated struct TypeScaleToken: Sendable, Hashable {",
        "    let size: CGFloat",
        "    let weight: Int",
        "    let trackingEm: CGFloat",
        "    let tabularDigits: Bool",
        "}",
        "",
        "nonisolated enum Tokens {",
        "    /// Нейтрали и семантика (свет / ночь).",
        "    enum Neutral {",
    ]
    for name, doc, light, dark in neutrals(ext):
        out.append(f"        /// {doc[:1].upper() + doc[1:]}.")
        out.append(f"        static let {name} = {swift_pair(light, dark)}")
    out.append("    }")
    out.append("")

    meta = ext["colorMeta"]
    out.append("    /// Неизменяемые бумага и графит: подписи и иконки на основных тонах «Гуаши» не инвертируются.")
    out.append("    enum Paper {")
    out.append(f"        static let surface: UInt32 = {hex_value(meta['paper-surface']['canonical'], 'paper-surface')}")
    out.append(f"        static let graphite: UInt32 = {hex_value(meta['graphite']['canonical'], 'graphite')}")
    out.append("    }")
    out.append("")

    heat = ext["darkTheme"]["heat"]
    if len(heat["light"]) != 5 or len(heat["dark"]) != 5:
        fail("darkTheme.heat: ожидалось 5 ступеней")
    pairs = [swift_pair(hex_value(l, "heat.light"), hex_value(d, "heat.dark")) for l, d in zip(heat["light"], heat["dark"])]
    out.append("    /// Шкала графита heat-0…4 (календарь, тепловая карта, «Привычки»).")
    out.append("    static let heat: [TokenPair] = [")
    out += [f"        {p}," for p in pairs]
    out.append("    ]")
    out.append("")

    out.append("    /// Радиусы (DESIGN.md → rounded), pt.")
    out.append("    enum Radius {")
    for key, value in yaml["rounded"].items():
        if key == "capsule":
            continue  # капсулы — `Capsule()`
        out.append(f"        static let {camel(key)}: CGFloat = {number(px(value, 'rounded.' + key))}")
    out.append("    }")
    out.append("")

    out.append("    /// Отступы (DESIGN.md → spacing), pt.")
    out.append("    enum Spacing {")
    for key, value in yaml["spacing"].items():
        out.append(f"        static let {camel(key)}: CGFloat = {number(px(value, 'spacing.' + key))}")
    out.append("    }")
    out.append("")

    out.append("    /// Размеры компонентов (DESIGN.md → components), pt.")
    out.append("    enum Size {")
    for component, props in yaml["components"].items():
        for prop in ["size", "width", "height"]:
            if prop in props:
                name = camel(component) + (prop[:1].upper() + prop[1:] if prop != "size" else "")
                out.append(f"        static let {name}: CGFloat = {number(px(props[prop], component + '.' + prop))}")
    out.append("    }")
    out.append("")

    out.append("    /// Шкала шрифтов (DESIGN.md → typography).")
    out.append("    enum TypeScale {")
    for key, props in yaml["typography"].items():
        size = px(props["fontSize"], key)
        weight = int(props["fontWeight"])
        tracking = props.get("letterSpacing", "0em")
        tracking_value = float(tracking[:-2]) if tracking.endswith("em") else fail(f"{key}: letterSpacing не в em")
        tabular = "true" if props.get("fontFeature") == "tnum" else "false"
        out.append(
            f"        static let {camel(key)} = TypeScaleToken(size: {number(size)}, weight: {weight}, "
            f"trackingEm: {number(tracking_value)}, tabularDigits: {tabular})"
        )
    out.append("    }")
    out.append("")

    plain, deep = shadows(ext)
    out.append("    /// Тени бумажных предметов (стекло рисует свои тени само).")
    out.append("    enum Shadow {")
    for name, x, y, blur, rgb, alpha, dalpha in plain:
        out.append(
            f"        static let {name} = ShadowToken(x: {number(x)}, y: {number(y)}, blur: {number(blur)}, "
            f"rgb: {rgb}, lightAlpha: {number(alpha)}, darkAlpha: {number(round(dalpha, 3))})"
        )
    out.append("        /// Выбранный образец: два слоя цвета deep категории.")
    out.append("        static let swatchSelected: [DeepShadowLayer] = [")
    for x, y, blur, alpha in deep:
        out.append(
            f"            DeepShadowLayer(x: {number(x)}, y: {number(y)}, blur: {number(blur)}, "
            f"lightAlpha: {number(alpha)}, darkAlpha: {number(round(dark_alpha(alpha), 3))}),"
        )
    out.append("        ]")
    out.append("    }")
    out.append("}")
    out.append("")

    out.append("extension GouacheTone {")
    out.append("    /// Значения тона из design.json.")
    out.append("    nonisolated var tokens: GouacheTokens {")
    out.append("        switch self {")
    for tone in gouache(ext, yaml["colors"]):
        out.append(f"        case .{tone['id']}: // {tone['name']}")
        out.append("            GouacheTokens(")
        out.append(f"                main: {tone['main']}, mainNight: {tone['mainNight']},")
        out.append(f"                tint: {tone['tint']}, deep: {tone['deep']}, darktint: {tone['darktint']},")
        out.append(f"                labelOnMain: {tone['labelOnMain']},")
        out.append(f"                shadesLight: {swift_list(tone['shadesLight'])},")
        out.append(f"                shadesDark: {swift_list(tone['shadesDark'])},")
        out.append(f"                labelsLight: {swift_list(tone['labelsLight'])},")
        out.append(f"                labelsDark: {swift_list(tone['labelsDark'])}")
        out.append("            )")
    out.append("        }")
    out.append("    }")
    out.append("}")
    out.append("")
    return "\n".join(out)


def main():
    design = json.loads(DESIGN_JSON.read_text(encoding="utf-8"))
    yaml = parse_front_matter(DESIGN_MD.read_text(encoding="utf-8"))
    text = render(design["extensions"], yaml)
    if "--check" in sys.argv[1:]:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != text:
            fail(f"{OUTPUT.relative_to(ROOT)} устарел: запустите python3 scripts/gen_tokens.py")
        print("Токены актуальны.")
        return
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"Записано: {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
