#!/usr/bin/env python3
"""Генерирует String Catalog `App/Resources/Localizable.xcstrings` из `design/copy.json` (ru)
и `design/copy.en.json` (en).

Использование:
    python3 scripts/gen_strings.py      # перезаписать каталог
    python3 scripts/check_copy.py       # сверить каталог с copy.json

Ключ = `id` из copy.json, значение = `final`, исходный язык — ru. Каталог руками не правится:
тексты меняются в copy.json / copy.en.json, затем скрипт запускается заново.

Английский (INTEGRATION §5.5) — тот же набор ключей: разбиения, подстановки и выделение — как у ru,
значения — таблица EN ниже; плюрализация en — формы one / other (в final через « | »).
Простые строки и разбиения без аргументов выводятся из en final сами.

Отступления от «ключ = id, значение = final» описаны явной таблицей SPEC ниже (не эвристикой):
  - «·» и «/» как перечисление вариантов → ключи `<id>.<вариант>`;
  - подстановки ({Категория}, {сумма}, пример «38 ⃅» и т. п.) → `%@`, позиционно `%1$@`, если их несколько;
  - количества → `%lld` с плюрализацией ru (one / few / many / other);
  - данные без текста (даты, числа, имена) → без ключа, собираются в коде;
  - составные фразы (сравнение с прошлым периодом) → шаблон + ключи фраз-отсылок;
  - выделенная часть фразы → разметка `**…**` (только ключи из EMPHASIZED), вывод — `L10n.attributed`.
Для каждого id в SPEC есть `expect`: сборка `final` из ключей каталога. check_copy.py проверяет,
что каталог воспроизводит `final` дословно (вместе с неразрывными пробелами, без `**`).
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COPY_JSON = ROOT / "design/copy.json"
COPY_EN_JSON = ROOT / "design/copy.en.json"
CATALOG = ROOT / "App/Resources/Localizable.xcstrings"
INFOPLIST_CATALOG = ROOT / "App/Resources/InfoPlist.xcstrings"  # имя под иконкой (app.displayName)
LANG = "ru"  # исходный язык каталога
LANGS = ("en", "ru")  # в каталоге — по алфавиту, как пишет Xcode
PLURAL_FORMS = {"ru": ("one", "few", "many", "other"), "en": ("one", "other")}
NB = " "  # неразрывный пробел
SIGN = "\u20c5"  # знак белорусского рубля (INTEGRATION §3.3.1); в примерах вместо «Br»


# ---------------------------------------------------------------------------
# Строки каталога

class Key:
    """Одна строка каталога.

    value  — текст или формат (`%@`, `%1$@`, `%lld`; литеральный процент — `%%`).
             Плюрализуемая часть внутри — `%#@имя@`, формы — в subs.
    plural — формы всей строки (one/few/many/other) с `%lld`: строка с одним числом.
    subs   — имя → (номер аргумента, формы с `%arg`): строка с несколькими аргументами.
    args   — описание аргументов для комментария в каталоге.
    """

    def __init__(self, value=None, *, plural=None, subs=None, args=""):
        assert (value is None) != (plural is None), "нужно value или plural"
        self.value, self.plural, self.subs, self.args = value, plural, subs or {}, args


def forms(one, few, many, other):
    return {"one": one, "few": few, "many": many, "other": other}


def noun(one, few, many, other):
    """Число + существительное: `%arg` — место числа (для substitutions)."""
    return forms(*(f"%arg{NB}{w}" for w in (one, few, many, other)))


# Формы ru: 1, 21 — one; 2–4, 22–24 — few; 0, 5–20, 25–30 — many; дробные — other.
TRATA = noun("трата", "траты", "трат", "траты")
DAY = noun("день", "дня", "дней", "дня")
CAT = noun("категория", "категории", "категорий", "категории")
SUBCAT = noun("подкатегория", "подкатегории", "подкатегорий", "подкатегории")
RUB = noun("рубль", "рубля", "рублей", "рубля")


def whole(f, prefix="", suffix=""):
    """Формы для plural (вся строка): `%arg` → `%lld`."""
    return {k: prefix + v.replace("%arg", "%lld") + suffix for k, v in f.items()}


# ---------------------------------------------------------------------------
# Таблица SPEC

class P(int):
    """Число-пример, записанное в final плейсхолдером ({N}): форма — по числу, вывод — текстом."""

    def __new__(cls, n, text):
        obj = int.__new__(cls, n)
        obj.text = text
        return obj

    def __str__(self):
        return self.text


class Spec:
    """Что даёт один id: ключи каталога и сборка final из них.

    kind: plain | fmt | split | alias (своих ключей нет, final собирается из чужих) | skip (не строка UI).
    expect(t) → строка, равная final; t(key, *args) рендерит строку каталога.
    also — проверки вариантов, которых нет в final (из risk/context): t → (строка, где она должна быть).
    """

    def __init__(self, kind, keys=None, expect=None, also=(), note="", nbsp_fix=False):
        self.kind, self.keys, self.expect, self.also, self.note = kind, keys or {}, expect, list(also), note
        self.nbsp_fix = nbsp_fix  # final расходится с правилом voice о неразрывном пробеле — сравнивать без него
        self.sep, self.parts = None, None  # у split(): из них en выводится из en final (en_plan)


SPEC = {}
# final по id — для разбиений, где части берутся из copy.json как есть.
_FINAL = {it["id"]: it["final"] for s in json.loads(COPY_JSON.read_text(encoding="utf-8"))["screens"]
          for it in s["items"]}


def fmt(id, value, *example, args="", **kw):
    """Строка с подстановками; ключ = id."""
    SPEC[id] = Spec("fmt", {id: Key(value, args=args, **kw)}, lambda t: t(id, *example))


def plural(id, plural_forms, *example, args=""):
    SPEC[id] = Spec("fmt", {id: Key(plural=plural_forms, args=args)}, lambda t: t(id, *example))


def split(id, sep, *parts, also=(), note=""):
    """Перечисление вариантов. Часть — (ключ, Key | None, пример-аргументы) или str.

    str — часть без ключа: данные (дата, число) или вариант, убранный решением (note).
    Key None — ключ определён в другом месте SPEC (повтор той же строки).
    """
    keys = {p[0]: p[1] for p in parts if not isinstance(p, str) and p[1] is not None}

    def expect(t):
        return sep.join(p if isinstance(p, str) else t(p[0], *(p[2] if len(p) > 2 else ())) for p in parts)

    SPEC[id] = Spec("split", keys, expect, also, note)
    SPEC[id].sep, SPEC[id].parts = sep, parts


def custom(id, keys, expect, also=(), kind="split", note="", nbsp_fix=False):
    SPEC[id] = Spec(kind, keys, expect, also, note, nbsp_fix)


def alias(id, expect, note):
    SPEC[id] = Spec("alias", {}, expect, note=note)


def skip(id, note):
    SPEC[id] = Spec("skip", note=note)


HINT = " · подсказка: "


def a11y(id, label, hint, label_example=(), label_args="", hint_example=(), **label_kw):
    """VoiceOver: имя (ключ = id) и подсказка (`<id>.hint`). label=str — данные без ключа."""
    keys = {f"{id}.hint": Key(hint, args="%@ — имя категории" if "%@" in hint else "")}
    if isinstance(label, Key):
        keys[id] = label
    elif label is not None and not label.startswith("{"):
        keys[id] = Key(label, args=label_args, **label_kw)

    def expect(t):
        head = label if isinstance(label, str) and label.startswith("{") else t(id, *label_example)
        return head + HINT + t(f"{id}.hint", *hint_example)

    SPEC[id] = Spec("split", keys, expect)


DATE = "%@ — короткая дата D7 («8 окт»)"

# Ключи с выделением `**…**`: часть фразы набрана SF 600 графитом, остальное — обычным/secondary
# (DESIGN.md «Callout», макеты design/mockups/light). Выводить через L10n.attributed.
# «по аналогии» — вариант того же места, который на макетах не нарисован.
EMPHASIZED = {
    "home.compare": "01-home, 02-home-ring, 04-stats, 05-stats-range: «38 ⃅ меньше»",
    "home.compare.more": "по аналогии с home.compare: «38 ⃅ больше»",
    "feed.dayHeader.today": "01-home, DESIGN.md «Заголовок дня»: «Сегодня» графитом, дата secondary",
    "feed.dayHeader.yesterday": "01-home: «Вчера» графитом, дата secondary",
    "cal.summary": "09-calendar, context «сумма полужирным»: «412,30 ⃅»",
    "stats.cats.caption.group": "04-stats, 05-stats-range: «Продукты: 35%»",
    "stats.cats.caption.sub": "04-stats-map-drill: «Супермаркет: 69%»",
    "stats.habits.insight.day": "04-stats: «по пятницам»",
    "stats.habits.insight.weekend": "04-stats: «В будни»",
    "stats.habits.insight.weekendMore": "по аналогии с weekend: «В выходные»",
    "stats.habits.insight.even": "по аналогии: вывод «почти поровну»",
    "stats.cats.caption.group.none": "по аналогии с stats.cats.caption.group: «без категории: 18%»",
    "stats.cats.caption.sub.none": "по аналогии с stats.cats.caption.sub: «без подкатегории: 40%»",
}

# --- Главная ---------------------------------------------------------------

split("period.segment.day-year", " · ",
      ("period.segment.day", Key("День")), ("period.segment.week", Key("Неделя")),
      ("period.segment.month", Key("Месяц")), ("period.segment.year", Key("Год")))
skip("header.month", "данные: название месяца (standalone, с заглавной); год — только если не текущий (D7)")
split("header.title.day", " · ",
      ("header.title.day.today", Key("Сегодня")), ("header.title.day.yesterday", Key("Вчера")),
      f"6{NB}окт")
skip("header.title.week", "данные: диапазон дат D7")
skip("header.title.year", "данные: номер года")

# Сравнение с прошлым периодом (D5): шаблон × фраза-отсылка. Отсылки — из правила D5 в voice.
custom("home.compare",
       {"home.compare": Key("на **%1$@ меньше**, чем %2$@", args="%1$@ — разница со знаком валюты, во фразе («38 ⃅»); %2$@ — отсылка home.compare.*.current/past или range.compare"),
        "home.compare.month.current": Key("в прошлом месяце")},
       lambda t: t("home.compare", f"38{NB}{SIGN}", t("home.compare.month.current")))
custom("home.compare.more", {"home.compare.more": Key("на **%1$@ больше**, чем %2$@", args="как у home.compare")},
       lambda t: t("home.compare.more", f"38{NB}{SIGN}", t("home.compare.month.current")), kind="fmt")
custom("home.compare.same", {"home.compare.same": Key("примерно как %@", args="%@ — отсылка (см. home.compare)")},
       lambda t: t("home.compare.same", t("home.compare.month.current")), kind="fmt")
custom("home.compare.noPrev",
       {"home.compare.noPrev": Key("%@ трат не было", args="%@ — отсылка (см. home.compare)"),
        "home.compare.noPrev.current": Key("%@ трат не было", args="%@ — отсылка идущего периода "
                                           "(home.compare.week/month/year.current): по-английски «by this time …»")},
       lambda t: t("home.compare.noPrev", t("home.compare.month.current")), kind="fmt",
       also=[lambda t, it: (t("home.compare.noPrev.current", t("home.compare.month.current")), it["final"])])
custom("home.compare.day",
       {"home.compare.day.current": Key("вчера"), "home.compare.day.past": Key("накануне")},
       lambda t: f"{t('home.compare.more', f'12{NB}{SIGN}', t('home.compare.day.current'))} · …, чем {t('home.compare.day.past')}")
custom("home.compare.week",
       {"home.compare.week.current": Key("на прошлой неделе"),
        "home.compare.week.past": Key("за %@", args="%@ — диапазон прошедшей недели D7 («21–27 сен»)")},
       lambda t: t("home.compare.more", f"12{NB}{SIGN}", t("home.compare.week.current")),
       also=[lambda t, it: ("чем " + t("home.compare.week.past", "21–27 сен"), it["context"])])
custom("home.compare.past",
       {"home.compare.month.past": Key("в %@", args="%@ — месяц в предложном падеже («августе»)")},
       lambda t: t("home.compare", f"38{NB}{SIGN}", t("home.compare.month.past", "августе")))
custom("home.compare.year",
       {"home.compare.year.current": Key("в прошлом году"),
        "home.compare.year.past": Key("в %@", args="%@ — год («2024»)")},
       lambda t: f"{t('home.compare', f'120{NB}{SIGN}', t('home.compare.year.current'))} · …, чем {t('home.compare.year.past', '2024')}")

split("home.empty.firstRun", " · ",
      ("home.empty.firstRun.title", Key("Пока нет трат")),
      ("home.empty.firstRun.body", Key("Нажмите «+», чтобы записать первую")))
# Пустой период: «пока нет» (период идёт) / «не было» (прошёл); формы — из context.
custom("home.empty.period",
       {"home.empty.period.in.current": Key("В %@ пока нет трат", args="%@ — месяц в предложном падеже («октябре»)"),
        "home.empty.period.in.past": Key("В %@ трат не было", args="%@ — месяц в предложном падеже («сентябре») или год («2025»)"),
        "home.empty.period.week.current": Key("На этой неделе пока нет трат"),
        "home.empty.period.day.current": Key("Сегодня пока нет трат"),
        "home.empty.period.day.past": Key("%@ трат не было", args=DATE),
        "home.empty.period.range.past": Key("С %1$@ по %2$@ трат не было", args="%1$@ — начало («2»), %2$@ — конец с месяцем («4 окт»)"),
        "home.empty.period.action": Key("К последней трате")},
       lambda t: f"{t('home.empty.period.in.past', 'сентябре')} · {t('home.empty.period.action')}",
       also=[lambda t, it: (t("home.empty.period.in.current", "октябре"), it["context"]),
             lambda t, it: (t("home.empty.period.week.current"), it["context"]),
             lambda t, it: (t("home.empty.period.day.current"), it["context"]),
             lambda t, it: (t("home.empty.period.day.past", "6 окт"), it["context"]),
             lambda t, it: (t("home.empty.period.range.past", "2", "4 окт"), it["context"]),
             lambda t, it: (t("home.empty.period.in.past", "2025"), it["context"])])
custom("home.empty.period.range.current",
       {"home.empty.period.range.current": Key("С %@ пока нет трат",
                                               args="%@ — начало своего периода D7 («10 окт»; не текущий год — «28 дек 2025»)")},
       lambda t: t("home.empty.period.range.current", f"10{NB}окт"),
       also=[lambda t, it: (t("home.empty.period.range.current", f"28{NB}дек{NB}2025"), it["context"])], kind="fmt")
fmt("feed.dayHeader.today", "**Сегодня** · %@", f"чт, 8{NB}окт", args="%@ — короткая дата с днём недели D7")
fmt("feed.dayHeader.yesterday", "**Вчера** · %@", f"ср, 7{NB}окт", args="%@ — короткая дата с днём недели D7")
skip("feed.dayHeader.other", "данные: короткая дата с днём недели D7 («Вт, 6 окт»)")
skip("feed.row.noNote", "данные: заголовок — имя подкатегории (или категории), подпись — имя категории")
skip("onboarding.hints", "пометка: подсказок первого запуска нет")

# --- Свой период -----------------------------------------------------------

skip("header.title.custom", "данные: диапазон дат D7")
skip("header.title.custom.cross", "данные: диапазон дат D7")
skip("header.title.custom.day", "данные: дата D7")
custom("range.compare",
       {"range.compare": Key("за %@", args="%@ — предыдущий отрезок своего периода D7 («2–4 окт»)")},
       lambda t: t("home.compare", f"23,80{NB}{SIGN}", t("range.compare", f"2–4{NB}окт")), kind="fmt")
plural("range.summary.lead", whole(DAY, "Потрачено за "), 3, args="%lld — число дней")
split("period.presets", " · ",
      "Эта неделя", "Этот месяц",
      ("period.preset.lastMonth", Key("Прошлый месяц")), ("period.preset.last30Days", Key(f"30{NB}дней")),
      ("period.preset.last3Months", Key(f"3{NB}месяца")), "Этот год",
      ("period.preset.allTime", Key("Всё время")),
      note="«Эта неделя», «Этот месяц», «Этот год» убраны: дублируют сегмент (INTEGRATION §8 п. 2)")
fmt("period.range.from", "С %@", f"24{NB}сен", args=DATE)
fmt("period.range.to", "По %@", f"8{NB}окт", args=DATE)
custom("period.range.meta",
       {"period.range.meta": Key(f"· %#@days@ ≈{NB}%2$@", subs={"days": (1, DAY)},
                                 args="%1$lld — число дней; %2$@ — округлённая сумма со знаком валюты («742 ⃅»)"),
        "period.range.meta.short": Key(plural=whole(DAY, "· "), args="%lld — число дней (запас при переполнении, risk)")},
       lambda t: t("period.range.meta", 15, f"742{NB}{SIGN}"),
       also=[lambda t, it: (t("period.range.meta.short", 15), it["final"])], kind="fmt")
fmt("period.apply", "Показать %@", f"24{NB}сен{NB}– 8{NB}окт", args="%@ — диапазон D7")

# --- Новая трата -----------------------------------------------------------

custom("add.batch.pill",
       {"add.batch.pill": Key("%#@count@ · %2$@", subs={"count": (1, TRATA)},
                              args="%1$lld — число трат; %2$@ — сумма без знака валюты («21,50»)")},
       lambda t: t("add.batch.pill", 2, "21,50"), kind="fmt")
skip("add.date.picked", "данные: дата D7")

# --- Выбор категории -------------------------------------------------------

split("picker.searchEmpty", " · ",
      ("picker.searchEmpty.title", Key("Ничего не найдено")),
      ("picker.searchEmpty.create", Key("Создать «%@»", args="%@ — текст поиска"), ("Кофейня",)))
split("picker.noCategories", " · ",
      ("picker.noCategories.title", Key("Категорий нет")),
      ("picker.noCategories.body", Key("Трату можно сохранить и без категории")))

# --- Календарь -------------------------------------------------------------

skip("cal.header.month", "данные: месяц и год (год серым — отдельный Text)")
custom("cal.summary",
       {"cal.summary": Key("**%1$@** за %#@days@ · больше всего %3$@", subs={"days": (2, DAY)},
                           args="%1$@ — итог со знаком валюты; %2$lld — число дней; %3$@ — дата D7")},
       lambda t: t("cal.summary", f"412,30{NB}{SIGN}", 8, f"2{NB}окт"), kind="fmt")
alias("cal.summary.empty",
      lambda t: f"{t('home.empty.period.in.past', 'ноябре')} · {t('home.empty.period.in.current', 'октябре')}",
      "home.empty.period.in.past / home.empty.period.in.current")
split("cal.weekdays", " · ", *((f"cal.weekdays.{d}", Key(w)) for d, w in
      zip(("mon", "tue", "wed", "thu", "fri", "sat", "sun"), ("Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"))))
fmt("cal.legend.title", "%@ за день", SIGN, args="%@ — знак валюты")
custom("cal.legend.items",
       {"cal.legend.items.below": Key("до %@", args="%@ — первый порог"),
        "cal.legend.items.from": Key("%@+", args="%@ — порог"),
        "cal.legend.items.belowShort": Key("<%@", args="%@ — первый порог; при трёхзначных порогах (risk)")},
       lambda t: " · ".join(["0", t("cal.legend.items.below", "25"), t("cal.legend.items.from", "25"),
                             t("cal.legend.items.from", "50"), t("cal.legend.items.from", "75")]),
       also=[lambda t, it: (t("cal.legend.items.belowShort", "125"), it["risk"])])
split("cal.cell.amount", " · ", "64,10", f"1{NB}234",
      ("cal.cell.amount.thousands", Key(f"%lld{NB}тыс", args="%lld — сумма в тысячах, от 10 000"), (12,)),
      note="до 10 000 — число без ключа (§5.2)")
skip("cal.day.title", "данные: полная дата («Четверг, 8 октября»), при переполнении — «Вс, 30 сентября»")
fmt("cal.addForDay", "Записать на %@", f"8{NB}окт", args=DATE)

# --- Статистика ------------------------------------------------------------

plural("stats.summary.lead", whole(DAY, "Потрачено за "), 8, args="%lld — число дней")
split("stats.summary.lead.variants", " · ",
      ("stats.summary.lead.today", Key("Потрачено сегодня")),
      ("stats.summary.lead.week", Key("Потрачено за неделю")),
      ("stats.summary.lead.month", Key("Потрачено за %@", args="%@ — месяц строчными («сентябрь»)"), ("сентябрь",)),
      ("stats.summary.lead.yearToDate", Key("Потрачено с начала года")),
      ("stats.summary.lead.year", Key(f"Потрачено за %@{NB}год", args="%@ — год («2025»)"), ("2025",)))
alias("stats.compare", lambda t: t("home.compare", f"38{NB}{SIGN}", t("home.compare.month.current")),
      "= home.compare (больше / столько же / пусто — home.compare.*)")
custom("stats.summary.meta",
       {"stats.summary.meta": Key("%#@count@ · в среднем %2$@ в день", subs={"count": (1, TRATA)},
                                  args="%1$lld — число трат; %2$@ — средняя со знаком валюты")},
       lambda t: t("stats.summary.meta", 18, f"51,54{NB}{SIGN}"), kind="fmt")
fmt("stats.cats.caption.group", f"Больше всего{NB}— **%1$@: %2$@**", "{Категория}", "{доля}%",
    args="%1$@ — имя категории; %2$@ — доля D7 («35%», «<1%»)")
fmt("stats.cats.caption.sub", f"Больше всего{NB}— **%1$@: %2$@**", "{Подкатегория}", "{доля}%",
    args="%1$@ — имя подкатегории; %2$@ — доля D7")
fmt("stats.cats.caption.sub.none", f"Больше всего{NB}— **без подкатегории: %@**", "40%", args="%@ — доля D7")
fmt("stats.cats.caption.group.none", f"Больше всего{NB}— **без категории: %@**", "18%", args="%@ — доля D7")
custom("stats.center.meta",
       {"stats.center.meta": Key("%1$@ · %#@count@", subs={"count": (2, TRATA)},
                                 args="%1$@ — знак валюты; %2$lld — число трат")},
       lambda t: t("stats.center.meta", SIGN, 18), kind="fmt")
fmt("stats.list.sub.share", "%@ категории", "69%", args="%@ — доля D7")
fmt("stats.list.noSub", "%@, подкатегорий нет", "6%", args="%@ — доля D7")
fmt("stats.days.avg", "в среднем %@", "51,54", args="%@ — сумма без знака валюты")
alias("stats.days.tip", lambda t: f"{t('header.title.day.today')}  57,20{NB}{SIGN}",
      "два Text: день (header.title.day.today / .yesterday или дата D7) и сумма")
skip("stats.months.tip", "данные: два Text, как stats.days.tip, — месяц в именительном падеже и сумма")
fmt("stats.pace.note", "к %@ при текущем темпе", f"31{NB}октября",
    args="%@ — конец периода в дательном («31 октября», «воскресенью»)")
split("stats.pace.note.variants", " · ",
      ("stats.pace.note", None, ("воскресенью",)),
      ("stats.pace.note", None, (f"31{NB}декабря",)),
      ("stats.pace.note.past", Key("итог за %@", args="%@ — прошедший период («сентябрь»)"), ("сентябрь",)))
split("stats.pace.legend", " · ", "октябрь", "сентябрь", ("stats.pace.legend.forecast", Key("прогноз")),
      note="названия периодов — данные")
fmt("stats.habits.note", "в среднем за день, %@", SIGN, args="%@ — знак валюты")
fmt("stats.habits.insight.weekend", "**В будни** тратится больше, чем в выходные")
fmt("stats.habits.insight.day", "Больше всего тратится **%@**", "по пятницам",
    args="%@ — «по» + день недели в дательном мн. ч. («по пятницам»)")
split("stats.habits.insight.variants", " · ",
      ("stats.habits.insight.weekendMore", Key("**В выходные** тратится больше, чем в будни")),
      ("stats.habits.insight.even", Key(f"В будни и в выходные{NB}— **почти поровну**")))
fmt("stats.year.heading", f"%@{NB}по дням", "2026", args="%@ — год")
split("stats.year.months", " · ", *((f"stats.year.months.{i}", Key(m)) for i, m in enumerate(
    ("Янв", "Фев", "Мар", "Апр", "Май", "Июн", "Июл", "Авг", "Сен", "Окт", "Ноя", "Дек"), 1)))
fmt("stats.top.meta", "%1$@ · %2$@", f"чт, 8{NB}окт", "Кафе и рестораны",
    args="%1$@ — короткая дата с днём недели D7; %2$@ — имя категории")
alias("stats.top.noNote", lambda t: f"Супермаркет / {t('stats.top.meta', f'чт, 8{NB}окт', 'Продукты')}",
      "заголовок — имя подкатегории (данные), подпись — stats.top.meta")
custom("viz.counts",
       {"viz.counts.groups": Key(plural=whole(CAT), args="%lld — число категорий"),
        "viz.counts.subs": Key(plural=whole(SUBCAT), args="%lld — число подкатегорий")},
       lambda t: (lambda g, s: f"{g} · {s} → «{g}» или «{s}»")(t("viz.counts.groups", 15), t("viz.counts.subs", 25)))
plural("viz.subCount", whole(SUBCAT), P(3, "{N}"), args="%lld — число подкатегорий")
plural("viz.more", whole(CAT, "Ещё "), 4, args="%lld — число свёрнутых категорий")
alias("viz.center.groups", lambda t: t("stats.center.meta", SIGN, 18), "= stats.center.meta")
fmt("viz.drill.share", "%@ всех трат", "35%", args="%@ — доля D7")
fmt("viz.drill.filter", "только %@", "Продукты", args="%@ — имя категории")
split("stats.empty.none", " · ",
      ("stats.empty.none.title", Key("Пока нет трат")),
      ("stats.empty.none.body", Key("Статистика появится после первой")))
alias("stats.empty.period",
      lambda t: f"{t('home.empty.period.in.past', 'сентябре')} · {t('home.empty.period.action')}",
      "= home.empty.period.*")
split("stats.fewData", " · ",
      ("stats.fewData.pace", Key("Прогноз появится через пару дней")),
      ("stats.fewData.habits", Key("Привычки появятся после двух недель трат")))

# --- Категории -------------------------------------------------------------

split("cat.title.edit", " · ",
      ("cat.title.edit.group", Key("Категория")), ("cat.title.edit.sub", Key("Подкатегория")))
fmt("cat.preview.caption", "Входит в категорию «%@»", "Кафе", args="%@ — имя категории")
split("cat.name.placeholder", " · ",
      ("cat.name.placeholder.sub", Key("Например, Кофе")),
      ("cat.name.placeholder.group", Key("Например, Продукты")))
fmt("cat.color.taken", "занят: %@", "Транспорт", args="%@ — имя категории, у которой этот цвет")
split("cat.icon.groups", " · ", *((f"cat.icon.group.{i}", Key(g)) for i, g in enumerate((
    "Еда и покупки", "Транспорт и поездки", "Дом и ЖКХ", "Связь и техника", "Здоровье и спорт",
    "Досуг", "Одежда и уход", "Семья и подарки", "Финансы и прочее"), 1)))
custom("cat.unarchive",
       {"cat.unarchive": Key("Вернуть из архива"), "cat.unarchive.short": Key("Из архива")},
       lambda t: t("cat.unarchive"),
       also=[lambda t, it: (t("cat.unarchive.short"), it["risk"])], kind="fmt")
skip("categories.active", "пометка: у секции нет заголовка")

# --- Настройки -------------------------------------------------------------

fmt("settings.currency.value", "%1$@ · %2$@", "Белорусский рубль", SIGN,
    args="%1$@ — название валюты; %2$@ — знак")
skip("currency.searchEmpty", "текст даёт система (ContentUnavailableView.search)")
skip("permissions", "пометка: разрешений Info.plist нет")

# --- Резервная копия -------------------------------------------------------

fmt("settings.backup.last", "Последняя копия: %@", f"1{NB}окт", args="%@ — дата D7 (год — если не текущий)")
custom("app.backupFileName",
       {"app.backupFileName": Key("Траты %@", args="%@ — дата yyyy-MM-dd; .json дописывает система")},
       lambda t: t("app.backupFileName", "2026-10-09") + ".json", kind="fmt")
fmt("import.currencyDiff", f"В копии другая валюта{NB}— %@. После восстановления можно выбрать, какую оставить.",
    "{код}", args="%@ — код валюты копии")
fmt("import.currencyQuestion",
    f"В копии{NB}— %1$@ (%2$@), в приложении{NB}— %3$@ (%4$@). Суммы не пересчитываются.",
    "{валюта}", "{код}", "{валюта}", "{код}",
    args="%1$@, %2$@ — название и код валюты копии; %3$@, %4$@ — валюты приложения")
fmt("import.useCurrency", "Использовать %@", "{код}", args="%@ — код валюты")
fmt("import.keepCurrency", "Оставить %@", "{код}", args="%@ — код валюты")
plural("import.missingCategory", forms(
    f"%lld{NB}трата без категории: её категории нет ни в копии, ни в приложении.",
    f"%lld{NB}траты без категории: их категорий нет ни в копии, ни в приложении.",
    f"%lld{NB}трат без категории: их категорий нет ни в копии, ни в приложении.",
    f"%lld{NB}траты без категории: их категорий нет ни в копии, ни в приложении."),
    P(5, "{N}"), args="%lld — число трат")

# --- Перенос трат из Monefy ------------------------------------------------

fmt("monefy.currencyDiff", "В файле указана валюта %1$@. Суммы запишутся в %2$@ как есть, без пересчёта.",
    "GBP", "BYN", args="%1$@ — коды валют файла через запятую; %2$@ — код валюты приложения")
custom("monefy.group.meta",
       {"monefy.group.meta": Key("%#@count@ · %2$@", subs={"count": (1, TRATA)},
                                 args="%1$lld — число трат категории Monefy; %2$@ — их сумма (фразой, с ⃅)")},
       lambda t: t("monefy.group.meta", 48, f"1{NB}234,50{NB}{SIGN}"), kind="fmt")
custom("monefy.group.a11y",
       {"monefy.group.a11y": Key("%1$@, %#@count@ на %3$@", subs={"count": (2, TRATA)},
                                 args="%1$@ — имя категории Monefy; %2$lld — число трат; %3$@ — сумма (a11y.money)")},
       lambda t: t("monefy.group.a11y", "Food", 48, f"1234{NB}рубля"), kind="fmt")
plural("monefy.import", whole(noun("трату", "траты", "трат", "траты"), "Перенести "), 1131,
       args="%lld — число трат к переносу (без «Не переносить»)")
plural("monefy.import.remaining", forms(
    f"Осталось выбрать для %lld{NB}категории Monefy.",
    f"Осталось выбрать для %lld{NB}категорий Monefy.",
    f"Осталось выбрать для %lld{NB}категорий Monefy.",
    f"Осталось выбрать для %lld{NB}категории Monefy."),
    3, args="%lld — число категорий Monefy без выбора")
split("monefy.importError", " / ",
      ("monefy.importError.title", Key("Не удалось перенести траты")),
      ("monefy.importError.message", Key("Данные в приложении не изменились. Попробуйте ещё раз.")))
for _id, _text in (("error.monefy.row.missingField", "Файл повреждён: в строке %lld не хватает данных. Выберите другой файл."),
                   ("error.monefy.row.badDate", "Файл повреждён: в строке %lld неверная дата. Выберите другой файл."),
                   ("error.monefy.row.badAmount", "Файл повреждён: в строке %lld неверная сумма. Выберите другой файл."),
                   ("error.monefy.row.amountTooLarge", "В строке %lld слишком большая сумма. Выберите другой файл.")):
    fmt(_id, _text, 12, args="%lld — номер строки файла (заголовок — строка 1)")

# --- Ошибки и подтверждения ------------------------------------------------

fmt("error.alert.title", "Не удалось %@", "{действие}", args="%@ — глагол с объектом («сохранить трату»)")
for _id in ("global.saveError", "add.save.error", "backup.exportPrepareError", "backup.exportSaveError"):
    _title, _message = _FINAL[_id].split(" / ")
    split(_id, " / ", (f"{_id}.title", Key(_title)), (f"{_id}.message", Key(_message)))
split("backup.importApplyError", " / ",
      ("backup.importApplyError.title", Key("Не удалось восстановить из копии")),
      ("backup.importApplyError.message", Key("Данные в приложении не изменились. %@",
                                              args="%@ — причина (error.backup.detail.*)"), ("{причина}",)))
fmt("error.store.duplicateCategoryName", "Категория «%@» уже есть.", "{имя}", args="%@ — название категории")
split("toast.deleted", " · ", ("toast.deleted.title", Key("Удалено")), ("toast.deleted.undo", Key("Отменить")))
split("add.discard", " / ",
      ("add.discard.title", Key("Не сохранять трату?")), ("add.discard.discard", Key("Не сохранять")),
      ("add.discard.keep", Key("Продолжить ввод")))
split("edit.discard", " / ",
      ("edit.discard.title", Key("Не сохранять изменения?")), ("edit.discard.discard", Key("Не сохранять")),
      ("edit.discard.keep", Key("Продолжить правку")))
split("catDelete.confirm", " · ",
      ("catDelete.confirm.group", Key("Удалить категорию «%@»?", args="%@ — имя категории"), ("Кафе",)),
      ("catDelete.confirm.sub", Key("Удалить подкатегорию «%@»?", args="%@ — имя подкатегории"), ("Кофе",)))
custom("cat.delete.sub.body",
       {"cat.delete.sub.body": Key(
           "%#@count@ в категории «%2$@» без подкатегории. Отменить это нельзя.",
           subs={"count": (1, forms(f"%arg{NB}трата останется", f"%arg{NB}траты останутся",
                                    f"%arg{NB}трат останутся", f"%arg{NB}траты останутся"))},
           args="%1$lld — число трат подкатегории; %2$@ — имя категории. Без трат — catDelete.confirmMessage")},
       lambda t: t("cat.delete.sub.body", 12, "Кафе"), kind="fmt")
custom("cat.delete.group.body",
       {"cat.delete.group.body": Key(
           "Вместе с ней %#@subs@, %#@count@ без категории. Отменить это нельзя.",
           subs={"subs": (1, forms(f"удалится %arg{NB}подкатегория", f"удалятся %arg{NB}подкатегории",
                                   f"удалятся %arg{NB}подкатегорий", f"удалятся %arg{NB}подкатегории")),
                 "count": (2, forms(f"%arg{NB}трата останется", f"%arg{NB}траты останутся",
                                    f"%arg{NB}трат останутся", f"%arg{NB}траты останутся"))},
           args="%1$lld — число подкатегорий; %2$lld — число трат")},
       lambda t: t("cat.delete.group.body", 3, 48), kind="fmt")
split("catDelete.button", " · ",
      ("catDelete.button.group", Key("Удалить категорию")), ("catDelete.button.sub", Key("Удалить подкатегорию")))
custom("import.replaceConfirmMessage",
       {"import.replaceConfirmMessage": Key(
           "Удалятся %#@count@ и %#@cats@, вместо них будут данные из копии. Отменить это нельзя.",
           subs={"count": (1, TRATA), "cats": (2, CAT)}, args="%1$lld — число трат; %2$lld — число категорий")},
       lambda t: t("import.replaceConfirmMessage", P(5, "{N}"), P(5, "{M}")), kind="fmt", nbsp_fix=True,
       note="в final «{M} категорий» с обычным пробелом — по правилу voice неразрывный")
fmt("currency.confirmButton", "Сменить на %@", "{код}", args="%@ — код валюты")
fmt("currency.confirmMessage", "Суммы не пересчитываются: 100 %1$@ станут 100 %2$@.", "{BYN}", "{USD}",
    args="%1$@ — код текущей валюты; %2$@ — код новой")

# --- VoiceOver -------------------------------------------------------------

custom("a11y.money",
       {"a11y.money": Key(plural=whole(RUB), args="%lld — целая сумма в рублях"),
        "a11y.money.fraction": Key(f"%@{NB}рубля", args="%@ — сумма с копейками («142,60»): дробные — всегда «рубля»")},
       lambda t: " · ".join([t("a11y.money.fraction", "142,60"), t("a11y.money", 5), t("a11y.money", 1)]))
a11y("header.month.a11y", "Период: %@", "Открывает выбор периода", ("октябрь 2026",),
     label_args="%@ — месяц и год строчными")
a11y("header.custom.a11y", "Свой период: %@", "Открывает выбор периода", (f"5–7{NB}октября",),
     label_args="%@ — диапазон с полными месяцами")
fmt("header.prev.a11y", "Предыдущий месяц, %@", "сентябрь", args="%@ — месяц строчными")
fmt("header.next.a11y", "Следующий месяц, %@", "ноябрь", args="%@ — месяц строчными")


def _arrows(word_m, word_f, word_pl):
    return {"day": Key(f"{word_m} день, %@", args="%@ — дата («7 октября»)"),
            "week": Key(f"{word_f} неделя, %@", args="%@ — диапазон («28 сентября – 4 октября»)"),
            "year": Key(f"{word_m} год, %@", args="%@ — год"),
            "custom": Key("%#@days@, %2$@", subs={"days": (1, forms(
                f"{word_m} %arg{NB}день", f"{word_pl} %arg{NB}дня", f"{word_pl} %arg{NB}дней", f"{word_pl} %arg{NB}дня"))},
                args="%1$lld — длина своего периода в днях; %2$@ — диапазон")}


_prev, _next = _arrows("Предыдущий", "Предыдущая", "Предыдущие"), _arrows("Следующий", "Следующая", "Следующие")
custom("header.arrows.a11y.other",
       {**{f"header.prev.a11y.{k}": v for k, v in _prev.items()},
        **{f"header.next.a11y.{k}": v for k, v in _next.items()}},
       lambda t: " · ".join([t("header.prev.a11y.day", f"7{NB}октября"),
                             t("header.prev.a11y.week", f"28{NB}сентября{NB}– 4{NB}октября"),
                             t("header.prev.a11y.year", "2025"), t("header.prev.a11y.custom", 3, f"2–4{NB}октября")]),
       also=[lambda t, it, k=k, a=a: (t(f"header.next.a11y.{k}", *a).replace("Следующ", "Предыдущ"),
                                      t(f"header.prev.a11y.{k}", *a))
             for k, a in (("day", ("x",)), ("week", ("x",)), ("year", ("x",)), ("custom", (1, "x")),
                          ("custom", (3, "x")), ("custom", (5, "x")))])
fmt("home.summary.a11y", "Итог и траты за %@", "октябрь", args="%@ — период («октябрь», «5–7 октября»)")
fmt("home.map.a11y", "Траты за %@ по категориям", "октябрь", args="%@ — период")
a11y("home.map.tile.a11y", "{Категория}, {сумма}, {доля}%", "Открывает категорию в статистике")
a11y("home.more.a11y", Key("Ещё %#@cats@, каждая меньше 3%%: %2$@; вместе %3$@", subs={"cats": (1, CAT)},
                           args="%1$lld — число свёрнутых категорий; %2$@ — их имена через запятую; %3$@ — сумма (a11y.money)"),
     "Открывает статистику", (3, "Связь, Здоровье, Другое", f"69,31{NB}рубля"))
alias("feed.dayHeader.a11y", lambda t: f"{t('header.title.day.today')}, четверг, 8{NB}октября, {t('a11y.money.fraction', '57,20')}",
      "перечисление данных: «Сегодня»/«Вчера» (header.title.day.*), полная дата, сумма (a11y.money)")
custom("feed.row.a11y",
       {"feed.row.a11y.delete": Key("Удалить"), "feed.row.a11y.repeat": Key("Повторить сегодня")},
       lambda t: f"Обед, Кафе и рестораны, Обеды, 44,70{NB}рубля · действия: "
                 f"{t('feed.row.a11y.delete')}, {t('feed.row.a11y.repeat')}",
       note="имя — перечисление данных через запятую (заметка, категория, подкатегория, сумма); ключи — имена действий")
custom("toast.deleted.a11y",
       {"toast.deleted.a11y": Key("Трата удалена"), "toast.deleted.a11y.undo": Key("Отменить")},
       lambda t: f"{t('toast.deleted.a11y')} · действие: {t('toast.deleted.a11y.undo')}")
split("add.saved.a11y", " · ",
      ("add.saved.a11y.save", Key("Трата сохранена")),
      ("add.saved.a11y.another", Key(plural=whole(TRATA, "Сохранено: "), args="%lld — число записанных трат"), (2,)))
a11y("add.batch.pill.a11y", Key("Записано: %#@count@ на %2$@", subs={"count": (1, TRATA)},
                                args="%1$lld — число трат; %2$@ — сумма (a11y.money)"),
     "Показывает записанные траты", (2, f"21,50{NB}рубля"))
skip("add.swatch.a11y", "данные: «{Подкатегория}, {Категория}»")
fmt("add.swatch.group.a11y", "%@, без подкатегории", "{Категория}", args="%@ — имя категории")
fmt("add.date.picked.a11y", "Дата: %@", f"понедельник, 5{NB}октября", args="%@ — день недели и полная дата")
a11y("add.note.a11y", "Заметка", "Добавляет заметку")
plural("add.quick.button.a11y", whole(RUB, "Прибавить "), P(5, "{N}"), args="%lld — быстрая сумма")
skip("edit.swatch.a11y", "данные: имя категории")
a11y("edit.note.a11y", "Заметка: %@", "Изменяет заметку", ("{текст}",), label_args="%@ — текст заметки")
fmt("picker.group.a11y", "%@, без подкатегории", "{Категория}", args="%@ — имя категории")
skip("picker.sub.a11y", "данные: «{Подкатегория}, {Категория}»")
a11y("cat.group.a11y", "Категория: %@", "Открывает выбор категории", ("{Категория}",),
     label_args="%@ — имя выбранной категории")
fmt("cat.color.a11y",
    f"Оттенки категории «%1$@»: первый{NB}— у «%2$@», второй{NB}— у новой подкатегории, остальные свободны",
    "{Категория}", "{имя}", args="%1$@ — категория; %2$@ — подкатегория с первым оттенком (пример для одной занятой)")
split("cat.color.names", " · ", *((f"cat.color.names.{tone}", Key(name)) for tone, name in zip(
    ("krapplak", "kinovar", "abrikos", "okhra", "olivka", "shalfey", "viridon", "tseruleum", "kobalt",
     "ultramarin", "ametist", "pion", "umbra", "slanets", "grafit"),
    ("Розовый", "Терракотовый", "Оранжевый", "Охристый", "Оливковый", "Зелёный", "Бирюзовый", "Лазурный",
     "Синий", "Васильковый", "Лиловый", "Сливовый", "Коричневый", "Серо-голубой", "Серый"))))
a11y("cal.header.a11y", "Месяц: %@", "Открывает выбор месяца", ("октябрь 2026",), label_args="%@ — месяц и год строчными")
fmt("cal.grid.a11y", "Траты по дням, %@", "октябрь 2026", args="%@ — месяц и год строчными")
custom("cal.day.a11y",
       {"cal.day.a11y.empty": Key("%@, трат нет", args="%@ — день недели и дата («четверг, 1 октября»)")},
       lambda t: "{День недели}, {d месяца}, {сумма} · без трат: " + t("cal.day.a11y.empty", "{День недели}, {d месяца}"),
       note="с тратами — перечисление данных (день недели, дата, сумма)")
fmt("cal.day.max.a11y", "%@, больше всего за месяц", "…", args="%@ — имя клетки дня (cal.day.a11y)")
fmt("cal.day.today.a11y", "Сегодня, %1$@, %2$@, выбран", f"четверг, 8{NB}октября", f"57,20{NB}рубля",
    args="%1$@ — день недели и дата; %2$@ — сумма (a11y.money)")
custom("cal.longPress.a11y", {"cal.longPress.a11y": Key("Записать трату на этот день")},
       lambda t: "действие: " + t("cal.longPress.a11y"), kind="fmt", note="имя действия (accessibilityAction)")
custom("cal.legend.a11y",
       {"cal.legend.a11y": Key("Шкала: %@ за день", args="%@ — пороги через запятую, последний — cal.legend.a11y.last; "
                                                          "без порогов — a11y.money для 0"),
        "cal.legend.a11y.below": Key("меньше %@", args="%@ — первый порог"),
        "cal.legend.a11y.from": Key("от %@", args="%@ — порог"),
        "cal.legend.a11y.last": Key(f"от %@{NB}рублей", args="%@ — последний порог (со словом валюты: по-английски "
                                                             "«75 rubles and up»)")},
       lambda t: t("cal.legend.a11y", ", ".join(["0", t("cal.legend.a11y.below", "25"), t("cal.legend.a11y.from", "25"),
                                                  t("cal.legend.a11y.from", "50"), t("cal.legend.a11y.last", "75")])))
fmt("cal.day.sheet.a11y", "Траты за %@", f"8{NB}октября", args="%@ — дата («8 октября»)")
fmt("cal.addForDay.a11y", "Записать трату на %@", f"8{NB}октября", args="%@ — дата («8 октября»)")
fmt("period.start.a11y", "Начало периода: %@", f"24{NB}сентября", args="%@ — дата («24 сентября»)")
custom("period.end.a11y",
       {"period.end.a11y": Key("Конец периода: %@", args="%@ — дата («8 октября»)"),
        "period.end.a11y.today": Key("Конец периода: %@, сегодня", args="%@ — дата, если конец — сегодня")},
       lambda t: t("period.end.a11y.today", f"8{NB}октября"),
       also=[lambda t, it: (t("period.end.a11y", f"8{NB}октября"), it["final"])])
a11y("stats.cats.back.a11y", "Категории", "Сворачивает «%@»", hint_example=("{Категория}",))
fmt("stats.map.a11y", "Плитки: траты за %@ по категориям", "октябрь", args="%@ — период")
a11y("stats.map.tile.a11y", "{Категория}, {сумма}, {доля}%", "Показывает подкатегории")
fmt("stats.strips.a11y", "Полосы: траты за %@ по категориям", "октябрь", args="%@ — период")
fmt("stats.strips.noSub.a11y", "%1$@, %2$@, %3$@, подкатегорий нет", "{Категория}", "{сумма}", "{доля}%",
    args="%1$@ — имя; %2$@ — сумма (a11y.money); %3$@ — доля D7")
fmt("stats.sun.a11y", f"Солнце: внутреннее кольцо{NB}— категории, внешнее{NB}— подкатегории. %@",
    "Продукты 35%, Кафе 21%, …", args="%@ — «имя доля» через запятую")
a11y("stats.center.back.a11y", "{Категория}, {сумма}", "Возвращает ко всем категориям")
fmt("stats.ring.a11y", "Кольцо: %@", "Продукты 35%, Кафе и рестораны 21%, …", args="%@ — «имя доля» через запятую")
a11y("stats.list.group.a11y", "%1$@, %2$@, %3$@ всех трат", "Показывает подкатегории",
     ("{Категория}", "{сумма}", "{доля}%"), label_args="%1$@ — имя; %2$@ — сумма (a11y.money); %3$@ — доля D7")
fmt("stats.list.sub.group.a11y", "%@: подкатегории", "Продукты", args="%@ — имя категории")
fmt("stats.days.a11y", "Траты по дням за %@", "октябрь", args="%@ — период")
skip("stats.days.bar.a11y", "данные: «Сегодня» / «Вчера» / дата и сумма")
fmt("stats.months.a11y", "Траты по месяцам за %@", "2026", args="%@ — год («2026»); у своего периода — диапазон")
skip("stats.months.bar.a11y", "данные: месяц (год — если не текущий) и сумма (a11y.money)")
custom("stats.pace.a11y",
       {"stats.pace.a11y": Key("Накопленные траты."),
        "stats.pace.a11y.current": Key(f"%1$@: %2$@ к %3$@{NB}числу.",
                                       args="%1$@ — период («Октябрь»); %2$@ — сумма (a11y.money); "
                                            "%3$@ — число месяца («8», по-английски «8th»)"),
        "stats.pace.a11y.previous": Key(f"%1$@: %2$@ к %3$@{NB}числу и %4$@ за месяц.",
                                        args="%1$@ — прошлый период; %2$@ — сумма к той же дате; %3$@ — число (как в current); "
                                             "%4$@ — итог"),
        "stats.pace.a11y.forecast": Key(f"Прогноз на %1$@ при текущем темпе{NB}— около %2$@",
                                        args="%1$@ — период («октябрь»); %2$@ — округлённая сумма (a11y.money)")},
       lambda t: " ".join([t("stats.pace.a11y"), t("stats.pace.a11y.current", "Октябрь", f"412,30{NB}рубля", "8"),
                           t("stats.pace.a11y.previous", "Сентябрь", f"450,30{NB}рубля", "8", f"1{NB}580{NB}рублей"),
                           t("stats.pace.a11y.forecast", "октябрь", f"1{NB}600{NB}рублей")]))
custom("stats.habits.a11y",
       {"stats.habits.a11y": Key("В среднем за день: %@", args="%@ — пункты stats.habits.a11y.item через stats.habits.a11y.separator"),
        "stats.habits.a11y.item": Key(f"%1$@{NB}— %2$@", args="%1$@ — день недели строчными; %2$@ — сумма (a11y.money)"),
        "stats.habits.a11y.separator": Key(", ", args="между пунктами (по-английски «; »)")},
       lambda t: t("stats.habits.a11y", t("stats.habits.a11y.separator").join([
           t("stats.habits.a11y.item", "понедельник", t("a11y.money", 72)),
           t("stats.habits.a11y.item", "вторник", t("a11y.money", 31)), "…",
           t("stats.habits.a11y.item", "воскресенье", t("a11y.money", 18))])))
fmt("stats.year.a11y",
    f"Траты за %1$@{NB}год по дням: одна клетка на день, заливка по шкале от 0{NB}до %2$@ и больше. Данные с %3$@ по %4$@",
    "2026", f"75{NB}рублей", f"1{NB}января", f"8{NB}октября",
    args="%1$@ — год; %2$@ — верхний порог шкалы («75 рублей»); %3$@, %4$@ — даты («1 января»)")
alias("stats.year.legend.a11y",
      lambda t: t("cal.legend.a11y", ", ".join(["0", t("cal.legend.a11y.below", "25"), t("cal.legend.a11y.from", "25"),
                                                 t("cal.legend.a11y.from", "50"), t("cal.legend.a11y.last", "75")])),
      "= cal.legend.a11y.* (одна шкала для календаря и карты года)")
split("stats.legacy.chartAxes", " · ",
      ("stats.legacy.chartAxes.amount", Key("Сумма")), ("stats.legacy.chartAxes.date", Key("Дата")),
      ("stats.legacy.chartAxes.weekday", Key("День недели")), ("stats.legacy.chartAxes.average", Key("В среднем за день")))
fmt("stats.dayView.a11y", "Траты по часам за %@", f"8{NB}октября", args="%@ — дата («8 октября»)")
custom("viz.more.a11y",
       {"viz.more.a11y": Key("Ещё %#@cats@, каждая меньше 3%%: %2$@; вместе %3$@, %4$@", subs={"cats": (1, CAT)},
                             args="%1$lld — число свёрнутых категорий; %2$@ — имена через запятую; %3$@ — сумма (a11y.money); %4$@ — доля D7")},
       lambda t: t("viz.more.a11y", 4, "Здоровье, Питомцы, Образование, Красота", f"57,10{NB}рубля", "8%"), kind="fmt")
custom("settings.categories.a11y",
       {"settings.categories.a11y": Key("Категории: %#@cats@ и %#@subs@", subs={"cats": (1, CAT), "subs": (2, SUBCAT)},
                                        args="%1$lld — число категорий; %2$lld — число подкатегорий")},
       lambda t: t("settings.categories.a11y", 12, 25), kind="fmt")
skip("settings.overview.a11y", "пометка: имена — viz.map.name / viz.ring.name, выбранный озвучивает система")
skip("cat.icon.a11y.rule", "пометка: правило именования иконок")

# Имена иконок: id вида cat.icon.name.<группа>.* → ключи cat.icon.name.<группа>.<номер>.
for _group, _first, _id in ((1, 1, "cat.icon.name.1.*"), (2, 1, "cat.icon.name.2.*"), (3, 1, "cat.icon.name.3.*"),
                            (4, 1, "cat.icon.name.4.*"), (5, 1, "cat.icon.name.5.*"), (6, 2, "cat.icon.name.6.*"),
                            (7, 1, "cat.icon.name.7.*"), (8, 1, "cat.icon.name.8.1-3"), (9, 3, "cat.icon.name.9.3-4")):
    _names = _FINAL[_id].split(" · ")
    split(_id, " · ", *((f"cat.icon.name.{_group}.{_first + i}", Key(n)) for i, n in enumerate(_names)))

skip("default.rename.note", "пометка для разработчика: новые имена — только для новых установок")


# ---------------------------------------------------------------------------
# Английский (design/copy.en.json, INTEGRATION §5.5)
#
# Ключи — те же, что у ru (SPEC): здесь только английские значения и сборка en final из них.
# Без записи en(...) id — простая строка (ключ = id, значение = en final) или разбиение split()
# без аргументов: значения частей берутся из en final по тому же разделителю (en_plan).

class EnSpec:
    """Сборка en final из ключей каталога; also, nbsp_fix — как у Spec."""

    def __init__(self, expect, also=(), nbsp_fix=False):
        self.expect, self.also, self.nbsp_fix = expect, list(also), nbsp_fix


EN = {}       # ключ каталога → английский Key
EN_SPEC = {}  # id → EnSpec


def en(id, keys, expect, also=(), nbsp_fix=False):
    for key, k in keys.items():
        if key in EN:
            raise SystemExit(f"Ошибка: en-ключ {key} задан дважды")
        EN[key] = k
    EN_SPEC[id] = EnSpec(expect, also, nbsp_fix)


def en_fmt(id, value, *example, **kw):
    """Строка с подстановками; ключ = id."""
    en(id, {id: Key(value, **kw)}, lambda t: t(id, *example))


def en_forms(id, examples, key=None):
    """Плюрализуемая строка: final — формы через « | » (примеры — аргументы каждой формы)."""
    key = key or id
    return lambda t: " | ".join(t(key, *ex) for ex in examples)


def en_noun(one, other):
    """Число + существительное (en): `%arg` — место числа."""
    return {"one": f"%arg{NB}{one}", "other": f"%arg{NB}{other}"}


EXPENSE = en_noun("expense", "expenses")
EN_DAY = en_noun("day", "days")
EN_CAT = en_noun("category", "categories")
EN_SUBCAT = en_noun("subcategory", "subcategories")
RUBLE = en_noun("ruble", "rubles")
MORE_CAT = en_noun("more category", "more categories")
EN_HINT = " · hint: "


def en_a11y(id, label, hint, label_example=(), hint_example=()):
    """VoiceOver: имя (ключ = id) и подсказка (`<id>.hint`), как a11y() у ru."""
    keys = {f"{id}.hint": Key(hint)}
    if isinstance(label, Key):
        keys[id] = label
    elif not label.startswith("{"):
        keys[id] = Key(label)

    def expect(t):
        head = label if isinstance(label, str) and label.startswith("{") else t(id, *label_example)
        return head + EN_HINT + t(f"{id}.hint", *hint_example)

    en(id, keys, expect)


S = f"{NB}{SIGN}"  # « ⃅» после суммы

# --- Главная ---------------------------------------------------------------

en("home.compare",
   {"home.compare": Key("**%1$@ less** than %2$@"), "home.compare.month.current": Key("this time last month")},
   lambda t: t("home.compare", f"38{S}", t("home.compare.month.current")))
en_fmt("home.compare.more", "**%1$@ more** than %2$@", f"38{S}", "this time last month")
en_fmt("home.compare.same", "About the same as %@", "this time last month")
en("home.compare.noPrev",
   {"home.compare.noPrev": Key("No expenses %@"), "home.compare.noPrev.current": Key("No expenses by %@")},
   lambda t: t("home.compare.noPrev.current", t("home.compare.month.current")),
   also=[lambda t, it: (t("home.compare.noPrev", t("home.compare.month.past", "August")), it["why"])])
en("home.compare.day",
   {"home.compare.day.current": Key("yesterday"), "home.compare.day.past": Key("the day before")},
   lambda t: f"{t('home.compare.more', f'12{S}', t('home.compare.day.current'))} · …than {t('home.compare.day.past')}")
en("home.compare.week",
   {"home.compare.week.current": Key("this time last week"), "home.compare.week.past": Key("%@")},
   lambda t: t("home.compare.more", f"12{S}", t("home.compare.week.current")),
   also=[lambda t, it: ("than " + t("home.compare.week.past", f"Sep{NB}21–27"), it["why"])])
en("home.compare.past", {"home.compare.month.past": Key("in %@")},
   lambda t: t("home.compare", f"38{S}", t("home.compare.month.past", "August")))
en("home.compare.year",
   {"home.compare.year.current": Key("this time last year"), "home.compare.year.past": Key("in %@")},
   lambda t: f"{t('home.compare', f'120{S}', t('home.compare.year.current'))} · …than {t('home.compare.year.past', '2025')}")
en("home.empty.period",
   {"home.empty.period.in.current": Key("No expenses yet in %@"),
    "home.empty.period.in.past": Key("No expenses in %@"),
    "home.empty.period.week.current": Key("No expenses yet this week"),
    "home.empty.period.day.current": Key("No expenses yet today"),
    "home.empty.period.day.past": Key("No expenses on %@"),
    "home.empty.period.range.past": Key("No expenses %1$@–%2$@"),
    "home.empty.period.action": Key("Go to Last Expense")},
   lambda t: f"{t('home.empty.period.in.past', 'September')} · {t('home.empty.period.action')}",
   also=[lambda t, it: (t("home.empty.period.week.current"), it["why"]),
         lambda t, it: (t("home.empty.period.day.current"), it["why"]),
         lambda t, it: (t("home.empty.period.day.past", f"Oct{NB}6"), it["why"]),
         lambda t, it: (t("home.empty.period.range.past", f"Oct{NB}2", "4"), it["why"]),
         lambda t, it: (t("home.empty.period.in.past", "2025"), it["why"])])
en("home.empty.period.range.current", {"home.empty.period.range.current": Key("No expenses since %@")},
   lambda t: t("home.empty.period.range.current", f"Oct{NB}10"),
   also=[lambda t, it: (t("home.empty.period.range.current", f"Dec{NB}28, 2025"), it["why"])])
en_fmt("feed.dayHeader.today", "**Today** · %@", f"Thu, Oct{NB}8")
en_fmt("feed.dayHeader.yesterday", "**Yesterday** · %@", f"Wed, Oct{NB}7")

# --- Свой период -----------------------------------------------------------

en("range.compare", {"range.compare": Key("%@")},
   lambda t: t("home.compare", f"23.80{S}", t("range.compare", f"Oct{NB}2–4")))
en("range.summary.lead", {"range.summary.lead": Key(plural=whole(EN_DAY, "Spent in "))},
   en_forms("range.summary.lead", [(1,), (3,)]))
en_fmt("period.range.from", "%@", f"Sep{NB}24")
en_fmt("period.range.to", "%@", f"Oct{NB}8")
en("period.range.meta",
   {"period.range.meta": Key(f"· %#@days@ ≈{NB}%2$@", subs={"days": (1, EN_DAY)}),
    "period.range.meta.short": Key(plural=whole(EN_DAY, "· "))},
   en_forms("period.range.meta", [(1, f"42{S}"), (15, f"742{S}")]),
   also=[lambda t, it: (t("period.range.meta.short", 15), it["final"])])
en_fmt("period.apply", "Show %@", f"Sep{NB}24{NB}–{NB}Oct{NB}8")

# --- Новая трата и выбор категории -----------------------------------------

en("add.batch.pill", {"add.batch.pill": Key("%#@count@ · %2$@", subs={"count": (1, EXPENSE)})},
   en_forms("add.batch.pill", [(1, "9.50"), (2, "21.50")]))
en("picker.searchEmpty",
   {"picker.searchEmpty.title": Key("No Results"), "picker.searchEmpty.create": Key("Create “%@”")},
   lambda t: f"{t('picker.searchEmpty.title')} · {t('picker.searchEmpty.create', 'Coffee Shop')}")

# --- Календарь -------------------------------------------------------------

en("cal.summary", {"cal.summary": Key("**%1$@** in %#@days@ · most on %3$@", subs={"days": (2, EN_DAY)})},
   lambda t: (t("cal.summary", f"9.50{S}", 1, f"Oct{NB}2").removesuffix(f" · most on Oct{NB}2") + " | "
              + t("cal.summary", f"412.30{S}", 8, f"Oct{NB}2")))
en("cal.summary.empty", {},
   lambda t: f"{t('home.empty.period.in.past', 'November')} · {t('home.empty.period.in.current', 'October')}")
en_fmt("cal.legend.title", "%@ per day", SIGN)
en("cal.legend.items",
   {"cal.legend.items.below": Key("<%@"), "cal.legend.items.from": Key("%@+"), "cal.legend.items.belowShort": Key("<%@")},
   lambda t: " · ".join(["0", t("cal.legend.items.below", "25"), t("cal.legend.items.from", "25"),
                         t("cal.legend.items.from", "50"), t("cal.legend.items.from", "75")]))
en("cal.cell.amount", {"cal.cell.amount.thousands": Key("%lldK")},
   lambda t: " · ".join(["64.10", "1,234", t("cal.cell.amount.thousands", 12)]))
en_fmt("cal.addForDay", "Add Expense on %@", f"Oct{NB}8")

# --- Статистика ------------------------------------------------------------

en("stats.summary.lead", {"stats.summary.lead": Key(plural=whole(EN_DAY, "Spent in "))},
   en_forms("stats.summary.lead", [(1,), (8,)]))
en("stats.summary.lead.variants",
   {"stats.summary.lead.today": Key("Spent today"), "stats.summary.lead.week": Key("Spent this week"),
    "stats.summary.lead.month": Key("Spent in %@"), "stats.summary.lead.yearToDate": Key("Spent this year"),
    "stats.summary.lead.year": Key("Spent in %@")},
   lambda t: " · ".join([t("stats.summary.lead.today"), t("stats.summary.lead.week"),
                         t("stats.summary.lead.month", "September"), t("stats.summary.lead.yearToDate"),
                         t("stats.summary.lead.year", "2025")]))
en("stats.compare", {}, lambda t: t("home.compare", f"38{S}", t("home.compare.month.current")))
en("stats.summary.meta", {"stats.summary.meta": Key("%#@count@ · daily average %2$@", subs={"count": (1, EXPENSE)})},
   en_forms("stats.summary.meta", [(1, f"9.50{S}"), (18, f"51.54{S}")]))
en_fmt("stats.cats.caption.group", "Most spent on **%1$@: %2$@**", "{Category}", "{share}%")
en_fmt("stats.cats.caption.sub", "Most spent on **%1$@: %2$@**", "{Subcategory}", "{share}%")
en_fmt("stats.cats.caption.sub.none", "Most spent **with no subcategory: %@**", "40%")
en_fmt("stats.cats.caption.group.none", "Most spent **without a category: %@**", "18%")
en("stats.center.meta", {"stats.center.meta": Key("%1$@ · %#@count@", subs={"count": (2, EXPENSE)})},
   en_forms("stats.center.meta", [(SIGN, 1), (SIGN, 18)]))
en_fmt("stats.list.sub.share", "%@ of the category", "69%")
en_fmt("stats.list.noSub", "%@ · no subcategories", "6%")
en_fmt("stats.days.avg", "average %@", "51.54")
en("stats.days.tip", {}, lambda t: f"{t('header.title.day.today')}  57.20{S}")
en_fmt("stats.pace.note", "by %@ at the current pace", f"October{NB}31")
en("stats.pace.note.variants", {"stats.pace.note.past": Key("total for %@")},
   lambda t: " · ".join([t("stats.pace.note", "Sunday"), t("stats.pace.note", f"December{NB}31"),
                         t("stats.pace.note.past", "September")]))
en_fmt("stats.habits.note", "daily average, %@", SIGN)
en_fmt("stats.habits.insight.weekend", "You spend more **on weekdays** than on weekends")
en_fmt("stats.habits.insight.day", "You spend the most **%@**", "on Fridays")
en("stats.habits.insight.variants",
   {"stats.habits.insight.weekendMore": Key("You spend more **on weekends** than on weekdays"),
    "stats.habits.insight.even": Key("Weekdays and weekends are **about even**")},
   lambda t: f"{t('stats.habits.insight.weekendMore')} · {t('stats.habits.insight.even')}")
en_fmt("stats.year.heading", "%@ by Day", "2026")
en_fmt("stats.top.meta", "%1$@ · %2$@", f"Thu, Oct{NB}8", "Dining")
en("stats.top.noNote", {}, lambda t: f"Supermarket / {t('stats.top.meta', f'Thu, Oct{NB}8', 'Groceries')}")
en("viz.counts",
   {"viz.counts.groups": Key(plural=whole(EN_CAT)), "viz.counts.subs": Key(plural=whole(EN_SUBCAT))},
   lambda t: (f"{t('viz.counts.groups', 15)} · {t('viz.counts.subs', 25)} → "
              f"“{t('viz.counts.groups', 1)} | {t('viz.counts.groups', 15)}” or "
              f"“{t('viz.counts.subs', 1)} | {t('viz.counts.subs', 25)}”"))
en("viz.subCount", {"viz.subCount": Key(plural=whole(EN_SUBCAT))}, en_forms("viz.subCount", [(1,), (P(3, "{N}"),)]))
en("viz.more", {"viz.more": Key(plural=whole(MORE_CAT))}, lambda t: t("viz.more", 4))
en("viz.center.groups", {}, en_forms("viz.center.groups", [(SIGN, 1), (SIGN, 18)], key="stats.center.meta"))
en_fmt("viz.drill.share", "%@ of all expenses", "35%")
en_fmt("viz.drill.filter", "%@ only", "Groceries")
en("stats.empty.period", {},
   lambda t: f"{t('home.empty.period.in.past', 'September')} · {t('home.empty.period.action')}")

# --- Категории -------------------------------------------------------------

en_fmt("cat.preview.caption", "Part of “%@”", "Dining")
en_fmt("cat.color.taken", "Used by %@", "Transport")
en("cat.unarchive", {"cat.unarchive": Key("Unarchive"), "cat.unarchive.short": Key("Unarchive")},
   lambda t: t("cat.unarchive"))

# --- Настройки и резервная копия -------------------------------------------

en_fmt("settings.currency.value", "%1$@ · %2$@", "Belarusian Ruble", SIGN)
en_fmt("settings.backup.last", "Last backup: %@", f"Oct{NB}1")
en("app.backupFileName", {"app.backupFileName": Key("Expenses Backup %@")},
   lambda t: t("app.backupFileName", "2026-10-09") + ".json")
en_fmt("import.currencyDiff",
       "This backup uses a different currency: %@. You can choose which one to keep after restoring.", "{code}")
en_fmt("import.currencyQuestion",
       "The backup uses %1$@ (%2$@); the app uses %3$@ (%4$@). Amounts aren’t converted.",
       "{currency}", "{code}", "{currency}", "{code}")
en_fmt("import.useCurrency", "Use %@", "{code}")
en_fmt("import.keepCurrency", "Keep %@", "{code}")
en("import.missingCategory", {"import.missingCategory": Key(plural={
    "one": f"%lld{NB}expense is now uncategorized: its category isn’t in the backup or the app.",
    "other": f"%lld{NB}expenses are now uncategorized: their categories aren’t in the backup or the app."})},
   en_forms("import.missingCategory", [(1,), (P(5, "{N}"),)]))

# --- Перенос трат из Monefy ------------------------------------------------

en_fmt("monefy.currencyDiff",
       "This file is set to %1$@. Amounts will be imported in %2$@ as is, without conversion.", "GBP", "BYN")
en("monefy.group.meta", {"monefy.group.meta": Key("%#@count@ · %2$@", subs={"count": (1, EXPENSE)})},
   en_forms("monefy.group.meta", [(1, f"9.50{S}"), (48, f"1,234.50{S}")]))
en("monefy.group.a11y", {"monefy.group.a11y": Key("%1$@, %#@count@ totaling %3$@", subs={"count": (2, EXPENSE)})},
   en_forms("monefy.group.a11y", [("Food", 1, f"9{NB}rubles"), ("Food", 48, f"1,234{NB}rubles")]))
en("monefy.import", {"monefy.import": Key(plural={"one": f"Import %lld{NB}Expense", "other": f"Import %lld{NB}Expenses"})},
   en_forms("monefy.import", [(1,), (1131,)]))
en("monefy.import.remaining", {"monefy.import.remaining": Key(plural={
    "one": f"%lld{NB}Monefy category still needs a choice.",
    "other": f"%lld{NB}Monefy categories still need a choice."})},
   en_forms("monefy.import.remaining", [(1,), (3,)]))
for _id, _text in (("error.monefy.row.missingField", "The file is damaged: line %lld is missing data. Choose a different file."),
                   ("error.monefy.row.badDate", "The file is damaged: line %lld has an incorrect date. Choose a different file."),
                   ("error.monefy.row.badAmount",
                    "The file is damaged: line %lld has an incorrect amount. Choose a different file."),
                   ("error.monefy.row.amountTooLarge", "Line %lld has an amount that’s too large. Choose a different file.")):
    en_fmt(_id, _text, 12)

# --- Ошибки и подтверждения ------------------------------------------------

en_fmt("error.alert.title", "Couldn’t %@", "{Action}")
en("backup.importApplyError",
   {"backup.importApplyError.title": Key("Couldn’t Restore Backup"),
    "backup.importApplyError.message": Key("Nothing in the app has changed. %@")},
   lambda t: f"{t('backup.importApplyError.title')} / {t('backup.importApplyError.message', '{reason}')}")
en_fmt("error.store.duplicateCategoryName", "A category named “%@” already exists.", "{name}")
en("catDelete.confirm",
   {"catDelete.confirm.group": Key("Delete Category “%@”?"), "catDelete.confirm.sub": Key("Delete Subcategory “%@”?")},
   lambda t: f"{t('catDelete.confirm.group', 'Dining')} · {t('catDelete.confirm.sub', 'Coffee')}")
en("cat.delete.sub.body",
   {"cat.delete.sub.body": Key("%#@count@ will stay in “%2$@” with no subcategory. This action can’t be undone.",
                               subs={"count": (1, EXPENSE)})},
   en_forms("cat.delete.sub.body", [(1, "Dining"), (12, "Dining")]))
en("cat.delete.group.body",
   {"cat.delete.group.body": Key(
       "%#@subs@ will also be deleted, and %#@count@ will become uncategorized. This action can’t be undone.",
       subs={"subs": (1, {"one": "Its subcategory", "other": f"Its %arg{NB}subcategories"}), "count": (2, EXPENSE)})},
   en_forms("cat.delete.group.body", [(1, 1), (3, 48)]))
en("import.replaceConfirmMessage",
   {"import.replaceConfirmMessage": Key(
       "%#@count@ and %#@cats@ will be deleted and replaced with data from the backup. This action can’t be undone.",
       subs={"count": (1, EXPENSE), "cats": (2, EN_CAT)})},
   en_forms("import.replaceConfirmMessage", [(1, 1), (P(5, "{N}"), P(5, "{M}"))]))
en_fmt("currency.confirmButton", "Change to %@", "{code}")
en_fmt("currency.confirmMessage", "Amounts aren’t converted: 100 %1$@ becomes 100 %2$@.", "BYN", "USD")

# --- VoiceOver -------------------------------------------------------------

en("a11y.money",
   {"a11y.money": Key(plural=whole(RUBLE)), "a11y.money.fraction": Key(f"%@{NB}rubles")},
   lambda t: " · ".join([t("a11y.money.fraction", "142.60"), t("a11y.money", 5), t("a11y.money", 1)]))
en_a11y("header.month.a11y", "Period: %@", "Opens period options", ("October 2026",))
en_a11y("header.custom.a11y", "Custom period: %@", "Opens period options", (f"October{NB}5–7",))
en_fmt("header.prev.a11y", "Previous month, %@", "September")
en_fmt("header.next.a11y", "Next month, %@", "November")


def _en_arrows(word):
    return {"day": Key(f"{word} day, %@"), "week": Key(f"{word} week, %@"), "year": Key(f"{word} year, %@"),
            "custom": Key("%#@days@, %2$@", subs={"days": (1, {"one": f"{word} day", "other": f"{word} %arg{NB}days"})})}


en("header.arrows.a11y.other",
   {**{f"header.prev.a11y.{k}": v for k, v in _en_arrows("Previous").items()},
    **{f"header.next.a11y.{k}": v for k, v in _en_arrows("Next").items()}},
   lambda t: " · ".join([t("header.prev.a11y.day", f"October{NB}7"),
                         t("header.prev.a11y.week", f"September{NB}28{NB}–{NB}October{NB}4"),
                         t("header.prev.a11y.year", "2025"), t("header.prev.a11y.custom", 3, f"October{NB}2–4")]),
   also=[lambda t, it, k=k, a=a: (t(f"header.next.a11y.{k}", *a).replace("Next", "Previous"),
                                  t(f"header.prev.a11y.{k}", *a))
         for k, a in (("day", ("x",)), ("week", ("x",)), ("year", ("x",)), ("custom", (1, "x")),
                      ("custom", (3, "x")))])
en_fmt("home.summary.a11y", "%@ total and expenses", "October")
en_fmt("home.map.a11y", "%@ expenses by category", "October")
en_a11y("home.map.tile.a11y", "{Category}, {amount}, {share}%", "Opens the category in Statistics")
en_a11y("home.more.a11y", Key("%#@cats@, each under 3%%: %2$@; %3$@ in total", subs={"cats": (1, MORE_CAT)}),
        "Opens Statistics", (3, "Connectivity, Health, Other", f"69.31{NB}rubles"))
en("feed.dayHeader.a11y", {},
   lambda t: f"{t('header.title.day.today')}, Thursday, October{NB}8, {t('a11y.money.fraction', '57.20')}")
en("feed.row.a11y", {"feed.row.a11y.delete": Key("Delete"), "feed.row.a11y.repeat": Key("Repeat Today")},
   lambda t: f"Lunch, Dining, Lunches, 44.70{NB}rubles · actions: {t('feed.row.a11y.delete')}, {t('feed.row.a11y.repeat')}")
en("toast.deleted.a11y", {"toast.deleted.a11y": Key("Expense deleted"), "toast.deleted.a11y.undo": Key("Undo")},
   lambda t: f"{t('toast.deleted.a11y')} · action: {t('toast.deleted.a11y.undo')}")
en("add.saved.a11y",
   {"add.saved.a11y.save": Key("Expense saved"), "add.saved.a11y.another": Key(plural=whole(EXPENSE, suffix=" saved"))},
   lambda t: f"{t('add.saved.a11y.save')} · {t('add.saved.a11y.another', 1)} | {t('add.saved.a11y.another', 2)}")
# «… in total» только у формы other — вся строка плюрализуется по числу трат (%1$lld), сумма — %2$@.
en_a11y("add.batch.pill.a11y", Key(plural={"one": f"%1$lld{NB}expense added, %2$@",
                                           "other": f"%1$lld{NB}expenses added, %2$@ in total"}),
        "Shows what you just added")
EN_SPEC["add.batch.pill.a11y"].expect = lambda t: (
    f"{t('add.batch.pill.a11y', 1, f'9.50{NB}rubles')} | {t('add.batch.pill.a11y', 2, f'21.50{NB}rubles')}"
    f"{EN_HINT}{t('add.batch.pill.a11y.hint')}")
en_fmt("add.swatch.group.a11y", "%@, no subcategory", "{Category}")
en_fmt("add.date.picked.a11y", "Date: %@", f"Monday, October{NB}5")
en_a11y("add.note.a11y", "Note", "Adds a note")
en("add.quick.button.a11y", {"add.quick.button.a11y": Key(plural=whole(RUBLE, "Add "))},
   lambda t: t("add.quick.button.a11y", P(5, "{N}")))
en_a11y("edit.note.a11y", "Note: %@", "Edits the note", ("{text}",))
en_fmt("picker.group.a11y", "%@, no subcategory", "{Category}")
en_a11y("cat.group.a11y", "Category: %@", "Opens category selection", ("{Category}",))
en_fmt("cat.color.a11y",
       "Shades of “%1$@”: the first is used by “%2$@”, the second goes to the new subcategory, the rest are free",
       "{Category}", "{name}")
en_a11y("cal.header.a11y", "Month: %@", "Opens month options", ("October 2026",))
en_fmt("cal.grid.a11y", "Expenses by day, %@", "October 2026")
en("cal.day.a11y", {"cal.day.a11y.empty": Key("%@, no expenses")},
   lambda t: "{Weekday}, {Month d}, {amount} · no expenses: " + t("cal.day.a11y.empty", "{Weekday}, {Month d}"))
en_fmt("cal.day.max.a11y", "%@, highest this month", "…")
en_fmt("cal.day.today.a11y", "Today, %1$@, %2$@, selected", f"Thursday, October{NB}8", f"57.20{NB}rubles")
en("cal.longPress.a11y", {"cal.longPress.a11y": Key("Add Expense on This Day")},
   lambda t: "action: " + t("cal.longPress.a11y"))


def _en_scale(t):
    return t("cal.legend.a11y", ", ".join(["0", t("cal.legend.a11y.below", "25"), t("cal.legend.a11y.from", "25"),
                                           t("cal.legend.a11y.from", "50"), t("cal.legend.a11y.last", "75")]))


en("cal.legend.a11y",
   {"cal.legend.a11y": Key("Scale: %@ per day"), "cal.legend.a11y.below": Key("under %@"),
    "cal.legend.a11y.from": Key("%@ and up"), "cal.legend.a11y.last": Key(f"%@{NB}rubles and up")},
   _en_scale)
en_fmt("cal.day.sheet.a11y", "Expenses on %@", f"October{NB}8")
en_fmt("cal.addForDay.a11y", "Add expense on %@", f"October{NB}8")
en_fmt("period.start.a11y", "Start date: %@", f"September{NB}24")
en("period.end.a11y", {"period.end.a11y": Key("End date: %@"), "period.end.a11y.today": Key("End date: %@, today")},
   lambda t: t("period.end.a11y.today", f"October{NB}8"),
   also=[lambda t, it: (t("period.end.a11y", f"October{NB}8"), it["final"])])
en_a11y("stats.cats.back.a11y", "Categories", "Collapses “%@”", hint_example=("{Category}",))
en_fmt("stats.map.a11y", "Tiles: %@ expenses by category", "October")
en_a11y("stats.map.tile.a11y", "{Category}, {amount}, {share}%", "Shows subcategories")
en_fmt("stats.strips.a11y", "Bars: %@ expenses by category", "October")
en_fmt("stats.strips.noSub.a11y", "%1$@, %2$@, %3$@, no subcategories", "{Category}", "{amount}", "{share}%")
en_fmt("stats.sun.a11y", "Sunburst: inner ring shows categories, outer ring shows subcategories. %@",
       "Groceries 35%, Dining 21%, …")
en_a11y("stats.center.back.a11y", "{Category}, {amount}", "Returns to all categories")
en_fmt("stats.ring.a11y", "Ring: %@", "Groceries 35%, Dining 21%, …")
en_a11y("stats.list.group.a11y", "%1$@, %2$@, %3$@ of all expenses", "Shows subcategories",
        ("{Category}", "{amount}", "{share}%"))
en_fmt("stats.list.sub.group.a11y", "%@: subcategories", "Groceries")
en_fmt("stats.days.a11y", "%@ expenses by day", "October")
en_fmt("stats.months.a11y", "%@ expenses by month", "2026")
en("stats.pace.a11y",
   {"stats.pace.a11y": Key("Running total."),
    "stats.pace.a11y.current": Key("%1$@: %2$@ as of the %3$@."),
    "stats.pace.a11y.previous": Key("%1$@: %2$@ as of the %3$@ and %4$@ for the month."),
    "stats.pace.a11y.forecast": Key("%1$@ forecast at the current pace: about %2$@")},
   lambda t: " ".join([t("stats.pace.a11y"), t("stats.pace.a11y.current", "October", f"412.30{NB}rubles", "8th"),
                       t("stats.pace.a11y.previous", "September", f"450.30{NB}rubles", "8th", f"1,580{NB}rubles"),
                       t("stats.pace.a11y.forecast", "October", f"1,600{NB}rubles")]))
en("stats.habits.a11y",
   {"stats.habits.a11y": Key("Daily average: %@"), "stats.habits.a11y.item": Key("%1$@, %2$@"),
    "stats.habits.a11y.separator": Key("; ")},
   lambda t: t("stats.habits.a11y", t("stats.habits.a11y.separator").join([
       t("stats.habits.a11y.item", "Monday", t("a11y.money", 72)),
       t("stats.habits.a11y.item", "Tuesday", t("a11y.money", 31)), "…",
       t("stats.habits.a11y.item", "Sunday", t("a11y.money", 18))])))
en_fmt("stats.year.a11y",
       f"%1$@{NB}expenses by day: one cell per day, shaded on a scale from 0 to %2$@ and up. Data from %3$@ to %4$@",
       "2026", f"75{NB}rubles", f"January{NB}1", f"October{NB}8")
en("stats.year.legend.a11y", {}, _en_scale)
en_fmt("stats.dayView.a11y", "Expenses by hour, %@", f"October{NB}8")
en("viz.more.a11y",
   {"viz.more.a11y": Key("%#@cats@, each under 3%%: %2$@; %3$@ in total, %4$@", subs={"cats": (1, MORE_CAT)})},
   lambda t: t("viz.more.a11y", 4, "Health, Pets, Education, Beauty", f"57.10{NB}rubles", "8%"))
en("settings.categories.a11y",
   {"settings.categories.a11y": Key("Categories: %#@cats@ and %#@subs@", subs={"cats": (1, EN_CAT), "subs": (2, EN_SUBCAT)})},
   en_forms("settings.categories.a11y", [(1, 1), (12, 25)]))


# ---------------------------------------------------------------------------
# Сборка каталога

def load_copy():
    return json.loads(COPY_JSON.read_text(encoding="utf-8"))


def load_copy_en():
    return json.loads(COPY_EN_JSON.read_text(encoding="utf-8"))


def items(copy):
    return [it for s in copy["screens"] for it in s["items"]]


def spec_for(item):
    """Spec id; без записи в SPEC — простая строка: ключ = id, значение = final."""
    if item["id"] in SPEC:
        return SPEC[item["id"]]
    id = item["id"]
    return Spec("plain", {id: Key(item["final"])}, lambda t: t(id))


def plan(copy):
    """Ключ каталога → (Key, id из copy.json). Ключ, заданный в нескольких id, должен совпадать."""
    result = {}
    for item in items(copy):
        for key, k in spec_for(item).keys.items():
            if key in result:
                raise SystemExit(f"Ошибка: ключ {key} задан дважды ({result[key][1]}, {item['id']})")
            result[key] = (k, item["id"])
    return result


def _auto_split(spec, final):
    """Разбиение без аргументов: части en final по тому же разделителю → (ключи, EnSpec) или None."""
    pieces = final.split(spec.sep)
    if len(pieces) != len(spec.parts):
        return None
    keys = {}
    for part, piece in zip(spec.parts, pieces):
        if isinstance(part, str):
            continue  # данные или убранный вариант — в en final просто текст
        key, k = part[0], part[1]
        if k is None or len(part) > 2 or k.plural or k.subs or "%" in k.value:
            return None
        keys[key] = Key(piece)

    def expect(t):
        return spec.sep.join(piece if isinstance(part, str) else t(part[0]) for part, piece in zip(spec.parts, pieces))

    return keys, EnSpec(expect)


def en_plan(copy, copy_en):
    """Английский: ключ каталога → Key и id → EnSpec. Набор ключей должен совпасть с ru (plan)."""
    finals = {it["id"]: it["final"] for it in items(copy_en)}
    keys, specs = dict(EN), dict(EN_SPEC)
    for item in items(copy):
        id, spec = item["id"], spec_for(item)
        if id in EN_SPEC or spec.kind == "skip":
            continue
        if id not in finals:
            raise SystemExit(f"Ошибка: id {id} нет в copy.en.json")
        if spec.kind == "plain":
            keys[id] = Key(finals[id])
            specs[id] = EnSpec(lambda t, id=id: t(id))
            continue
        derived = _auto_split(spec, finals[id]) if spec.parts is not None else None
        if derived is None:
            raise SystemExit(f"Ошибка: для {id} ({spec.kind}) нужна запись en(...) в gen_strings.py")
        keys.update(derived[0])
        specs[id] = derived[1]
    ru_keys = set(plan(copy))
    if set(keys) != ru_keys:
        raise SystemExit(f"Ошибка: ключи en и ru расходятся: только en {sorted(set(keys) - ru_keys)}, "
                         f"только ru {sorted(ru_keys - set(keys))}")
    return keys, specs


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural_unit(f, lang):
    return {"plural": {cat: unit(f[cat]) for cat in PLURAL_FORMS[lang] if cat in f}}


def localization(k, lang):
    if k.plural:
        return {"variations": plural_unit(k.plural, lang)}
    loc = unit(k.value)
    if k.subs:
        loc["substitutions"] = {
            name: {"argNum": num, "formatSpecifier": "lld", "variations": plural_unit(f, lang)}
            for name, (num, f) in sorted(k.subs.items())}
    return loc


def comment(item, key, k):
    text = f"{item['element']}. {item['context']}".strip(" .") if item["context"] else item["element"]
    if key != item["id"]:
        text = f"copy.json {item['id']}: {text}"
    if k.args:
        text += f". Аргументы: {k.args}"
    if key in EMPHASIZED:
        text += ". Выделение **…** — SF 600 графитом, выводить через L10n.attributed"
    return text


def build(copy, copy_en):
    by_id = {it["id"]: it for it in items(copy)}
    english, _ = en_plan(copy, copy_en)
    strings = {}
    for key, (k, id) in sorted(plan(copy).items()):
        keys = {"ru": k, "en": english[key]}
        strings[key] = {"comment": comment(by_id[id], key, k), "extractionState": "manual",
                        "localizations": {lang: localization(keys[lang], lang) for lang in LANGS}}
    return {"sourceLanguage": LANG, "strings": strings, "version": "1.0"}


def build_infoplist(copy, copy_en):
    """Имя приложения под иконкой на языке интерфейса (`app.displayName`): ключ Info.plist CFBundleDisplayName."""
    names = {lang: next(it["final"] for it in items(c) if it["id"] == "app.displayName")
             for lang, c in (("ru", copy), ("en", copy_en))}
    item = next(it for it in items(copy) if it["id"] == "app.displayName")
    entry = {"comment": comment(item, "CFBundleDisplayName", Key("")),
             "extractionState": "manual",
             "localizations": {lang: unit(names[lang]) for lang in LANGS}}
    return {"sourceLanguage": LANG, "strings": {"CFBundleDisplayName": entry}, "version": "1.0"}


def dumps(catalog):
    # Как пишет Xcode: два пробела, « : », кириллица без экранирования.
    return json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n"


def main():
    copy, copy_en = load_copy(), load_copy_en()
    catalog = build(copy, copy_en)
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(dumps(catalog), encoding="utf-8")
    INFOPLIST_CATALOG.write_text(dumps(build_infoplist(copy, copy_en)), encoding="utf-8")
    kinds = {}
    for item in items(copy):
        kinds[spec_for(item).kind] = kinds.get(spec_for(item).kind, 0) + 1
    print(f"{CATALOG.relative_to(ROOT)}: {len(catalog['strings'])} ключей из {len(items(copy))} id "
          f"({', '.join(f'{k} {v}' for k, v in sorted(kinds.items()))}), языки {', '.join(LANGS)}; "
          f"{INFOPLIST_CATALOG.relative_to(ROOT)}: CFBundleDisplayName")


if __name__ == "__main__":
    main()
