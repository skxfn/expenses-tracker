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

## Ловушки
- Xcode 26: без установленной iOS-платформы (`xcodebuild -downloadPlatform iOS`) сборка по схеме падает «iOS 26.5 is not installed»; `-target Expenses -sdk iphoneos` при этом собирается.
- SwiftData: `transaction {}` при ошибке не откатывает — нужен явный `rollback()`, после него заново выбрать модели (старые ссылки падают «model instance was invalidated»).
- Даты в бэкапе — через `BackupFormat` (ISO 8601 с округлением до мс). `.iso8601`/наивный `ISO8601FormatStyle` теряют доли секунды и сдвигают дату на 1 мс за цикл.
- `DateInterval.contains` включает `end` — для периодов не использовать.
- Новые SF Symbols — только доступные в iOS ≤ 17.0 (сверка по `CoreGlyphs.bundle/.../name_availability.plist` в `CatalogTests`); `NSImage(systemSymbolName:)` на свежем macOS этого не гарантирует.
