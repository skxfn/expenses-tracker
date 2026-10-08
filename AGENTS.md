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
- GitHub-репо ещё не создан: плейсхолдер `DEFAULT_REPO` в `scripts/update_source.py` (в Actions — `$GITHUB_REPOSITORY`). Репо и релизы должны быть публичными — иначе SideStore не скачает.
- UI: тонкие View + `@Observable` модели рядом (`ExpenseFormModel`, `StatisticsModel`, `BackupModel`…). При внедрении дизайна переписываются только View и `App/Shared`, модели остаются.
- Дизайн не утверждён: текущий UI временный на системных компонентах. Референсы — `design/` (`gallery.html` открывать в обычном браузере), Mobbin MCP требует платный план. Dime (open-source) под GPL-3.0 — код не копировать.

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
- SideStore может дописать к Bundle ID `.<TeamID>`: ничего не хардкодить по bundle ID; смена Apple ID = новое пустое приложение (данные — только через бэкап).
- Новые SF Symbols — только доступные в iOS ≤ 17.0 (сверка по `CoreGlyphs.bundle/.../name_availability.plist` в `CatalogTests`); `NSImage(systemSymbolName:)` на свежем macOS этого не гарантирует.
