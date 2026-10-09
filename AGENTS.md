# Журнал проекта «Траты»

## Решения
- Bundle ID `com.skxfn.expenses` постоянный: смена = новое приложение в SideStore и потеря данных.
- Проект генерируется XcodeGen из `project.yml`, `Expenses.xcodeproj` закоммичен (чистый клон собирается без xcodegen). После правки `project.yml` — `xcodegen generate`. `App/` — synced folder: новые файлы в проект добавлять не нужно.
- Логика (модели, хранилище, статистика, экспорт) — в пакете `Packages/ExpenseCore`, тесты гоняются на маке: `cd Packages/ExpenseCore; swift test`. UI — в `App/`.
- Сумма хранится как `Int64` в сотых долях валюты (`amountMinor`), валюта одна на приложение. Без Double для денег.
- Модели вложены в `SchemaV1` (VersionedSchema) + `ExpenseMigrationPlan`: любое изменение моделей — через новую версию схемы, иначе данные пользователя потеряются при обновлении.
- Все изменения данных — через `ExpenseStore` (валидация + save), `@Query` — только чтение.
- При запуске `CurrencySettings.ensureCurrencyCode` вызывается до показа сумм: иначе смена региона iOS молча поменяет валюту всех записей.
- Статистика считается по `ExpenseRecord` (value type); интервалы полуоткрытые `[start, end)`. Средняя/кривая текущего периода — по сегодня включительно.
- Формат бэкапа версионируется `formatVersion` (сейчас 1); при несовместимой смене поднять `BackupFormat.currentVersion` и сохранить чтение старых версий.
- Версия — только в `Config/Version.xcconfig`; `scripts/build_ipa.sh` поднимает её сам, в CI — `--no-bump`. Тег релиза строго `v<MARKETING_VERSION>`, иначе Action падает.
- Репо — публичный `skxfn/expenses-tracker` (`DEFAULT_REPO` в `scripts/update_source.py`, в Actions — `$GITHUB_REPOSITORY`). Должен оставаться публичным — иначе SideStore не скачает релизы.
- UI: тонкие View + `@Observable` модели рядом (`ExpenseFormModel`, `StatisticsModel`, `BackupModel`…). При внедрении дизайна переписываются только View и `App/Shared`, модели остаются.
- Дизайн не утверждён: текущий UI временный на системных компонентах. Референсы — `design/` (`gallery.html` открывать в обычном браузере), Mobbin MCP требует платный план. Dime (open-source) под GPL-3.0 — код не копировать.
- Дизайн (скилл impeccable) — холст https://claude.ai/artifact/Wkh9EydSQCAbkH1tYXHPDB, страницы «Итерация 2», «План интерфейса», «Итерация 1». Выбрано направление «Образцы»: бумага #F3F0EA + графит #221D18, цифры — Unbounded, UI — SF, цвет несут только данные. Продуктовый контекст для скилла — `PRODUCT.md`.
- Палитра категорий — «Гуашь» (12 цветов одной громкости; значения — доска «Палитра «Гуашь» и иконки» на холсте) вместо `CategoryPalette`: большие площади только тинтами, насыщенный — мелкими элементами. Старые hex в данных и бэкапах переводить по таблице «старый → новый» (это замена значений, не новая схема).
- Иконки категорий — MingCute Fill (Apache 2.0) вместо SF Symbols; в данных лежат имена SF Symbols — нужна таблица соответствий при запуске и в импортёре.
- Deployment target — iOS 26: Liquid Glass на всём «хроме», без `#available` и запасного вида.
- Решения по экранам: тап по иконке у веера на главном → статистика категории (там — анимация раскрытия веера); быстрые суммы фиксированные 5/10/20/50/100 и прибавляются к введённой; своя калькуляторная клавиатура пользователю не нравится; веер должен выдерживать 15 категорий.
- Пожелания пользователя к дизайну: добавление как в Spendly, главный как в Monefy (кольцо с иконками + лента), редактор категории как в EZ Money Tracker, красивый календарь отдельной вкладкой, статистика S1–S4 все, свой произвольный период и на главном, иконки категорий — из библиотек (не эмодзи).

## Ловушки
- Xcode 26: без установленной iOS-платформы (`xcodebuild -downloadPlatform iOS`) сборка по схеме падает «iOS 26.5 is not installed»; `-target Expenses -sdk iphoneos` при этом собирается.
- SwiftData: `transaction {}` при ошибке не откатывает — нужен явный `rollback()`, после него заново выбрать модели (старые ссылки падают «model instance was invalidated»).
- Даты в бэкапе — через `BackupFormat` (ISO 8601 с округлением до мс). `.iso8601`/наивный `ISO8601FormatStyle` теряют доли секунды и сдвигают дату на 1 мс за цикл.
- `DateInterval.contains` включает `end` — для периодов не использовать.
- SideStore сверяет sha256, размер и version/build `.ipa` с `source.json`: ассет релиза не перезаливать без `update_source.py`.
- Без подписи entitlements в `.app` не встраиваются — `build_ipa.sh` проверяет `CODE_SIGN_ENTITLEMENTS` проекта. `-showBuildSettings` — только с `-target` (со схемой без iOS-платформы падает).
- Симулятор: `xcodebuild -scheme Expenses -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath <scratch>`; сборка через `-target … CODE_SIGNING_ALLOWED=NO` ставится, но `simctl launch` на ней зависает. В DEBUG: `-demoData YES` (демо-траты в пустую базу), `-debugTab statistics|settings`.
- `.fileExporter` сам дописывает `.json` по типу — `defaultFilename` передавать без расширения.
- Не читать свойства удалённой SwiftData-модели: sheet-маршруты и модели форм копируют `id`/флаги при открытии.
- Swift Charts на iOS 17: свой тип `AxisContent` объявить нельзя — общие оси через функцию `some AxisContent`.
- Устройство пользователя — iOS 27. SideStore нужен ≥ 0.7.0-alpha (0.6.4 и старше не логинятся после изменений Apple в сент. 2026). На iOS 27 шорткат «Refresh All Apps» может падать с ADI -45061 — обход: SideStore → Settings → User Customizations → Reset adi.db (SideStore#1596).
- SideStore может дописать к Bundle ID `.<TeamID>`: ничего не хардкодить по bundle ID; смена Apple ID = новое пустое приложение (данные — только через бэкап).
- Новые SF Symbols — только доступные в iOS ≤ 17.0 (сверка по `CoreGlyphs.bundle/.../name_availability.plist` в `CatalogTests`); `NSImage(systemSymbolName:)` на свежем macOS этого не гарантирует.
