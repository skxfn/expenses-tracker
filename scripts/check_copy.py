#!/usr/bin/env python3
"""Сверяет String Catalog `App/Resources/Localizable.xcstrings` с `design/copy.json` (ru) и `design/copy.en.json` (en).

Использование:
    python3 scripts/check_copy.py

Проверяет:
  - каталог и InfoPlist.xcstrings совпадают с тем, что выдаёт gen_strings.py (руками не правлены, не устарели);
  - каждый id из copy.json покрыт: ключ, разбиение, общая фраза (alias) или пропуск с причиной;
    id в copy.en.json — те же;
  - для каждого языка строки каталога, подставленные примерами из SPEC (en — EN_SPEC), дают `final`
    дословно (с неразрывными пробелами, разметка выделения `**` не учитывается), а варианты из
    risk/context/why встречаются там, откуда взяты;
  - разметка `**…**` — только у ключей gen_strings.EMPHASIZED и парная, в обоих языках; других знаков
    Markdown в строках нет (SwiftUI `Text("ключ")` разбирает Markdown в любой строке каталога);
  - нет лишних и недостающих ключей; у каждого ключа оба языка; плюрализация — полные формы
    (ru: one/few/many/other, en: one/other);
  - строк из `dropped` и запрещённых слов (§5.1, D1; en — glossary и voice copy.en.json) нет;
  - каталог компилируется `xcstringstool` (если есть Xcode), в каждом языке — все ключи.
Выход 1 и список ошибок, если что-то не так.
"""
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_strings as g  # noqa: E402

# Оставлены намеренно: в dropped «stats.legacy.*, кроме «Без категории» и имён осей».
DROPPED_EXCEPTIONS = {"stats.legacy.uncategorized", "stats.legacy.chartAxes"}
FORBIDDEN = [
    (re.compile(r"[Рр]асход"), "«расход» — в интерфейсе «трата» (glossary)"),
    (re.compile(r"Не получилось"), "заголовок ошибки — «Не удалось …» (voice)"),
    (re.compile(r"\bOK\b"), "«ОК» — кириллицей (voice)"),
    (re.compile(r"[Ээ]кспорт"), "«Сохранить копию» (D8)"),
    (re.compile(r"[Бб]экап"), "«резервная копия» (glossary)"),
    (re.compile(r"[Гг]рупп"), "слово «группа» не используется (D1)"),
]
FORBIDDEN_EN = [
    (re.compile(r"\b[Tt]ransactions?\b"), "«expense», не «transaction» (glossary, E1)"),
    (re.compile(r"\b[Ss]pendings\b"), "«spendings» в английском нет (glossary)"),
    (re.compile(r"\b[Ww]e\b"), "«we» не используется (E4)"),
    (re.compile(r"\bOops\b"), "без «Oops» (voice)"),
    (re.compile(r"\bBr\b"), "знак рубля — U+20C5, не «Br» (E7)"),
    (re.compile(r"\be\.g\."), "«For example», не «e.g.» (voice)"),
]
EMPHASIS = "**"
MARKDOWN = re.compile(r"[*_`\[\]\\~]")  # после удаления парных ** таких знаков быть не должно
SPECIFIER = re.compile(r"%(?:(\d+)\$)?(@|lld|%)")
SUBSTITUTION = re.compile(r"%#@(\w+)@")


def category(n, lang):
    """Категория плюрализации (CLDR) для целого числа: ru — one/few/many, en — one/other."""
    n = abs(int(n))
    if lang == "en":
        return "one" if n == 1 else "other"
    if n % 10 == 1 and n % 100 != 11:
        return "one"
    if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14:
        return "few"
    return "many"


def printf(fmt, args):
    """`%@`, `%lld`, `%N$@`, `%N$lld`, `%%` — как String(format:)."""
    leftover = SPECIFIER.sub("", fmt)
    if "%" in leftover:
        raise ValueError(f"неизвестный спецификатор в «{fmt}»")
    used, seq = set(), iter(range(len(args) + 1))

    def repl(m):
        if m.group(2) == "%":
            return "%"
        index = int(m.group(1)) - 1 if m.group(1) else next(seq)
        if index >= len(args):
            raise ValueError(f"в «{fmt}» не хватает аргумента {index + 1}")
        value = args[index]
        if m.group(2) == "lld" and not isinstance(value, int):
            raise ValueError(f"%lld получает не число: {value!r}")
        used.add(index)
        return str(value)

    return SPECIFIER.sub(repl, fmt), used


def render(entry, args, lang):
    loc = entry["localizations"][lang]
    if "variations" in loc:
        fmt = loc["variations"]["plural"][category(args[0], lang)]["stringUnit"]["value"]
        text, used = printf(fmt, args)
        used.add(0)  # число выбрало форму, даже если в форме его нет
    else:
        subs, used_subs = loc.get("substitutions", {}), set()

        def repl(m):
            sub = subs[m.group(1)]
            n = args[sub["argNum"] - 1]
            used_subs.add(sub["argNum"] - 1)
            form = sub["variations"]["plural"][category(n, lang)]["stringUnit"]["value"]
            return form.replace("%arg", str(n))

        text, used = printf(SUBSTITUTION.sub(repl, loc["stringUnit"]["value"]), args)
        used |= used_subs
    if used != set(range(len(args))):
        raise ValueError(f"использованы аргументы {sorted(i + 1 for i in used)} из {len(args)}")
    return text


def nbsp(s):
    return s.replace(g.NB, " ")


def plain(s):
    """Текст без разметки выделения — так его видит пользователь."""
    return s.replace(EMPHASIS, "")


def check_markup(strings, lang, errors):
    marked = set()
    for key, entry in strings.items():
        for value in values(entry, lang):
            if EMPHASIS in value:
                marked.add(key)
                marks = [m.start() for m in re.finditer(re.escape(EMPHASIS), value)]
                # Markdown не выделит «** текст» и «текст **»: внутри пары пробел у края недопустим.
                broken = len(marks) % 2 or any(
                    value[o + 2:o + 3].isspace() or value[c - 1:c].isspace() or c == o + 2
                    for o, c in zip(marks[::2], marks[1::2]))
                if broken:
                    errors.append(f"{key} [{lang}]: непарная или оторванная пробелом разметка в «{value}»")
            if MARKDOWN.search(plain(value)):
                errors.append(f"{key} [{lang}]: знак Markdown в «{value}» — SwiftUI Text разберёт его как разметку")
    for key in sorted(marked ^ set(g.EMPHASIZED)):
        errors.append(f"{key} [{lang}]: разметка ** {'есть, но ключа нет в EMPHASIZED' if key in marked else 'в EMPHASIZED, но в строке её нет'}")


def number_count_ok(value, lang, form, placeholder):
    """В форме ровно одно число; en «one» может обойтись без него («Its subcategory», «Previous day»)."""
    if placeholder == "%arg":
        count = value.count("%arg")
    else:
        count = [m.group(2) for m in SPECIFIER.finditer(value)].count("lld")
    return count == 1 or (lang == "en" and form == "one" and count == 0)


def check_structure(key, entry, errors):
    loc = entry.get("localizations", {})
    if set(loc) != set(g.LANGS):
        errors.append(f"{key}: языки {sorted(loc)} вместо {sorted(g.LANGS)}")
        return
    for lang in g.LANGS:
        check_localization(key, loc[lang], lang, errors)


def check_localization(key, loc, lang, errors):
    forms = g.PLURAL_FORMS[lang]
    if "variations" in loc:
        f = loc["variations"]["plural"]
        if tuple(sorted(f)) != tuple(sorted(forms)):
            errors.append(f"{key} [{lang}]: формы {sorted(f)}, нужны {forms}")
        for name, u in f.items():
            if not number_count_ok(u["stringUnit"]["value"], lang, name, "%lld"):
                errors.append(f"{key}.{name} [{lang}]: в форме должен быть ровно один %lld")
        return
    value = loc["stringUnit"]["value"]
    subs = loc.get("substitutions", {})
    referenced = SUBSTITUTION.findall(value)
    if sorted(referenced) != sorted(subs):
        errors.append(f"{key} [{lang}]: в строке {referenced}, в substitutions {sorted(subs)}")
    if subs and re.search(r"%(@|lld)", SUBSTITUTION.sub("", value)):
        errors.append(f"{key} [{lang}]: при substitutions остальные аргументы — только позиционные (%2$@)")
    for name, sub in subs.items():
        f = sub["variations"]["plural"]
        if tuple(sorted(f)) != tuple(sorted(forms)) or sub.get("formatSpecifier") != "lld":
            errors.append(f"{key}/{name} [{lang}]: формы {sorted(f)}, спецификатор {sub.get('formatSpecifier')}")
        for form, u in f.items():
            if not number_count_ok(u["stringUnit"]["value"], lang, form, "%arg"):
                errors.append(f"{key}/{name}.{form} [{lang}]: в форме должен быть ровно один %arg")


def values(entry, lang):
    loc = entry["localizations"][lang]
    if "variations" in loc:
        return [u["stringUnit"]["value"] for u in loc["variations"]["plural"].values()]
    return [loc["stringUnit"]["value"]] + [u["stringUnit"]["value"] for s in loc.get("substitutions", {}).values()
                                           for u in s["variations"]["plural"].values()]


def dropped_ids(copy):
    """id из первой скобки каждой записи dropped (во второй — то, что их заменило)."""
    result = []
    for text in copy["dropped"]:
        m = re.search(r"\(([^)]*)\)", text)
        if m:
            result += re.findall(r"[A-Za-z]\w*(?:\.(?:[\w-]+|\*))+", m.group(1))
    return result


def compile_check(strings, errors):
    if not shutil.which("xcrun"):
        print("предупреждение: xcrun не найден, компиляция каталога не проверена")
        return
    with tempfile.TemporaryDirectory() as out:
        run = subprocess.run(["xcrun", "xcstringstool", "compile", str(g.CATALOG), "-o", out],
                             capture_output=True, text=True)
        if run.returncode != 0:
            errors.append(f"xcstringstool: {run.stderr.strip() or run.stdout.strip()}")
            return
        for lang in g.LANGS:
            compiled = set()
            for ext in (".strings", ".stringsdict"):
                path = Path(out) / f"{lang}.lproj" / (g.CATALOG.stem + ext)
                if path.exists():
                    compiled |= set(plistlib.loads(path.read_bytes()))
            if compiled != set(strings):
                errors.append(f"xcstringstool [{lang}]: скомпилировано {len(compiled)} ключей из {len(strings)}; "
                              f"нет: {sorted(set(strings) - compiled)[:5]}")


def check_language(lang, copy_l, spec_of, strings, errors):
    """final каждого id этого языка собирается из каталога дословно; варианты — там, откуда взяты."""
    def t(key, *args):
        if key not in strings:
            raise KeyError(f"нет ключа {key}")
        return render(strings[key], args, lang)

    for item in g.items(copy_l):
        if g.spec_for(item).kind == "skip":
            continue
        spec = spec_of(item)
        try:
            actual = plain(spec.expect(t))
            expected = item["final"]
            same = nbsp(actual) == nbsp(expected) if spec.nbsp_fix else actual == expected
            if not same:
                errors.append(f"{item['id']} [{lang}]: каталог даёт {actual!r}, в final {expected!r}")
            for also in spec.also:
                text, where = also(t, item)
                if nbsp(plain(text)) not in nbsp(where):
                    errors.append(f"{item['id']} [{lang}]: вариант {text!r} не найден в {where!r}")
        except (KeyError, ValueError, IndexError) as e:
            errors.append(f"{item['id']} [{lang}]: {e.args[0] if e.args else e!r}")


def main():
    copy, copy_en = g.load_copy(), g.load_copy_en()
    catalog_text = g.CATALOG.read_text(encoding="utf-8")
    catalog = json.loads(catalog_text)
    strings = catalog["strings"]
    errors = []

    if catalog.get("sourceLanguage") != g.LANG:
        errors.append(f"sourceLanguage {catalog.get('sourceLanguage')} вместо {g.LANG}")
    if g.dumps(g.build(copy, copy_en)) != catalog_text:
        errors.append("каталог не совпадает с выводом gen_strings.py: запустите python3 scripts/gen_strings.py")
    infoplist = g.INFOPLIST_CATALOG.read_text(encoding="utf-8") if g.INFOPLIST_CATALOG.exists() else ""
    if g.dumps(g.build_infoplist(copy, copy_en)) != infoplist:
        errors.append(f"{g.INFOPLIST_CATALOG.name} не совпадает с выводом gen_strings.py")

    ids = [it["id"] for it in g.items(copy)]
    if len(ids) != len(set(ids)):
        errors.append(f"в copy.json повторяются id: {sorted({i for i in ids if ids.count(i) > 1})}")
    ids_en = [it["id"] for it in g.items(copy_en)]
    if sorted(ids_en) != sorted(ids):
        errors.append(f"id copy.en.json и copy.json расходятся: {sorted(set(ids) ^ set(ids_en))}")
    for id in sorted(set(g.SPEC) - set(ids)):
        errors.append(f"SPEC: id {id} нет в copy.json")
    for id in sorted(set(g.EN_SPEC) - set(ids)):
        errors.append(f"EN_SPEC: id {id} нет в copy.json")

    planned = g.plan(copy)
    for key in sorted(planned.keys() - strings.keys()):
        errors.append(f"нет ключа {key} (id {planned[key][1]})")
    for key in sorted(strings.keys() - planned.keys()):
        errors.append(f"лишний ключ {key}")
    for key, entry in strings.items():
        check_structure(key, entry, errors)

    for item in g.items(copy):
        spec = g.spec_for(item)
        if spec.kind == "skip" and not spec.note:
            errors.append(f"{item['id']}: пропуск без причины")
    _, en_specs = g.en_plan(copy, copy_en)
    check_language("ru", copy, g.spec_for, strings, errors)
    check_language("en", copy_en, lambda item: en_specs[item["id"]], strings, errors)

    for id in dropped_ids(copy):
        if "*" in id:
            pattern = re.compile(re.escape(id).replace(r"\*", r"[\w.-]+") + "$")
            hits = [i for i in ids if pattern.match(i) and i not in DROPPED_EXCEPTIONS]
        else:
            hits = [i for i in ids if i == id] + [k for k in strings if k == id]
        for hit in hits:
            errors.append(f"{hit}: в dropped, но остался")

    for lang, forbidden in (("ru", FORBIDDEN), ("en", FORBIDDEN_EN)):
        for key, entry in strings.items():
            for value in values(entry, lang):
                for pattern, why in forbidden:
                    if pattern.search(value):
                        errors.append(f"{key} [{lang}]: «{value}» — {why}")
        check_markup(strings, lang, errors)
    compile_check(strings, errors)

    if errors:
        print(f"Ошибок: {len(errors)}")
        for e in errors:
            print(" -", e)
        sys.exit(1)
    kinds = {}
    for item in g.items(copy):
        kind = g.spec_for(item).kind
        kinds[kind] = kinds.get(kind, 0) + 1
    print(f"OK: {len(strings)} ключей × {len(g.LANGS)} языка, {len(ids)} id "
          f"({', '.join(f'{k} {v}' for k, v in sorted(kinds.items()))})")


if __name__ == "__main__":
    main()
