#!/usr/bin/env python3
"""Кладёт иконки категорий MingCute Fill в App/Resources/Assets.xcassets/Categories (§3.7).

Источник — npm-пакет `mingcute_icon` (Apache 2.0, https://github.com/Richard9394/MingCute):
    curl -LO https://registry.npmjs.org/mingcute_icon/-/mingcute_icon-<версия>.tgz; tar -xzf mingcute_icon-*.tgz
    python3 scripts/import_mingcute.py package [имя-fill …]

Без имён берётся каталог `CategoryIconCatalog` (Core), набор design/migration.json
(icons[].mingcute, defaultCategories[].icon, iconFallback) и EXTRA. Имя ассета = имя MingCute (`basket-fill`; в пакете файл `svg/<раздел>/basket_fill.svg`).
SVG упрощается для Asset Catalog: убирается служебный прозрачный контур 24×24, заливка — чёрная
(ассет — шаблон, цвет задаёт код), добавляется viewBox. Только stdlib.
"""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App" / "Resources" / "Assets.xcassets" / "Categories"
CATALOG_SWIFT = ROOT / "Packages" / "ExpenseCore" / "Sources" / "ExpenseCore" / "Catalog" / "CategoryIconCatalog.swift"
LICENSE_OUT = ROOT / "App" / "Resources" / "Licenses" / "MingCute-LICENSE.txt"
SVG_NS = "http://www.w3.org/2000/svg"

# Иконки вне migration.json, нужные интерфейсу.
EXTRA = [
    "question-fill",  # «Без категории» (CategoryPaint.uncategorizedIconName)
]

CONTENTS_INFO = {"author": "xcode", "version": 1}


def fail(message):
    sys.exit(f"import_mingcute: {message}")


def default_names():
    migration = json.loads((ROOT / "design" / "migration.json").read_text(encoding="utf-8"))
    names = {item["mingcute"] for item in migration["icons"]}
    names |= {item["icon"] for item in migration["defaultCategories"]}
    names.add(migration["iconFallback"])
    names |= set(re.findall(r'"([a-z0-9-]+-fill)"', CATALOG_SWIFT.read_text(encoding="utf-8")))
    return sorted(names | set(EXTRA))


def clean_svg(source: Path) -> bytes:
    ET.register_namespace("", SVG_NS)
    tree = ET.parse(source)
    svg = tree.getroot()
    svg.set("viewBox", svg.get("viewBox", "0 0 24 24"))
    for parent in svg.iter():
        for child in list(parent):
            if child.tag == f"{{{SVG_NS}}}path" and child.get("d", "").startswith("M24 0v24H0V0z"):
                parent.remove(child)  # служебная рамка 24×24 из исходников MingCute
    for element in svg.iter():
        fill = element.get("fill")
        if fill and fill != "none":
            element.set("fill", "#000000")
    return ET.tostring(svg, encoding="utf-8")


def write_imageset(name: str, svg: bytes):
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{name}.svg").write_bytes(svg)
    contents = {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": CONTENTS_INFO,
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


def main():
    if len(sys.argv) < 2:
        fail("укажите папку распакованного пакета mingcute_icon (package)")
    package = Path(sys.argv[1])
    meta = json.loads((package / "package.json").read_text(encoding="utf-8"))
    files = {path.stem.replace("_", "-"): path for path in (package / "svg").glob("*/*.svg")}
    names = sys.argv[2:] or default_names()
    missing = [name for name in names if name not in files]
    if missing:
        fail(f"в пакете нет: {', '.join(missing)}")

    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": CONTENTS_INFO}, indent=2) + "\n", encoding="utf-8")
    for name in names:
        write_imageset(name, clean_svg(files[name]))

    LICENSE_OUT.parent.mkdir(parents=True, exist_ok=True)
    header = (
        f"MingCute Icon — {meta['name']} {meta['version']}, https://github.com/Richard9394/MingCute\n"
        "Иконки категорий в Assets.xcassets/Categories изменены: удалён служебный прозрачный контур 24×24,\n"
        "заливка приведена к шаблону (цвет задаёт приложение).\n\n"
    )
    LICENSE_OUT.write_text(header + (package / "LICENSE").read_text(encoding="utf-8"), encoding="utf-8")
    print(f"{meta['name']} {meta['version']}: {len(names)} иконок → {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
