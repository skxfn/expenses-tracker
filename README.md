# Траты

Личный трекер расходов для iPhone (SwiftUI, iOS 17+). Без App Store и платного аккаунта разработчика: собирается неподписанный `.ipa`, а [SideStore](https://sidestore.io) подписывает его бесплатным Apple ID и переподписывает каждые 7 дней.

## Сборка

Нужен Xcode 26 с установленной платформой iOS (Xcode → Settings → Components).

```bash
./scripts/build_ipa.sh            # поднять версию (patch +1, build +1) и собрать
./scripts/build_ipa.sh --no-bump  # собрать текущую версию
```

Результат — `dist/Expenses-<версия>.ipa`, лог xcodebuild — `build/xcodebuild.log`. Скрипт останавливается, если в проекте есть entitlements, недоступные бесплатному Apple ID. После сборки с поднятием версии закоммитьте `Config/Version.xcconfig`.

## Версия

Единственный источник — `Config/Version.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). SideStore видит обновление, только если версия выросла.

```bash
./scripts/bump_version.sh         # 1.0.0 (1) -> 1.0.1 (2)
./scripts/bump_version.sh minor   # 1.0.1 (2) -> 1.1.0 (3); есть и major
```

`build_ipa.sh` без `--no-bump` вызывает его сам.

## Релиз через GitHub

1. Поднять версию и закоммитить `Config/Version.xcconfig`.
2. Создать и запушить тег, равный версии: `git tag v1.0.1`, `git push origin main v1.0.1`.
3. Action `Release` (`.github/workflows/release.yml`, раннер `macos-26`, Xcode 26.6) соберёт `.ipa`, выложит его в GitHub Releases и закоммитит обновлённый `source.json` в основную ветку.

Можно запустить и вручную: Actions → Release → Run workflow — тег `v<MARKETING_VERSION>` создастся сам. Сборка падает, если тег не совпадает с версией или такой релиз уже есть. Если основная ветка защищена (branch protection), разрешите пуш для GitHub Actions, иначе `source.json` не обновится. В публичном репозитории раннеры GitHub бесплатны, в приватном macOS-минуты платные (примерно в 10 раз дороже Linux).

Репозиторий — [skxfn/expenses-tracker](https://github.com/skxfn/expenses-tracker) (публичный), задан в одном месте: `DEFAULT_REPO` в `scripts/update_source.py`. В Actions вместо него берётся реальный `$GITHUB_REPOSITORY`.

Без Actions: собрать `.ipa`, создать релиз с тегом `v<версия>` и приложить файл, затем `python3 scripts/update_source.py dist/Expenses-<версия>.ipa` и закоммитить `source.json`.

## Установка на iPhone

### Один раз: SideStore

1. Заведите отдельный Apple ID для подписи. SideStore входит в Apple через сторонний anisette-сервер, и аккаунты при этом иногда блокируются (FAQ SideStore) — основной аккаунт рисковать не стоит.
2. Установите SideStore по официальной инструкции: [docs.sidestore.io](https://docs.sidestore.io/docs/installation/prerequisites). Компьютер (утилита iloader) нужен один раз, на iPhone — LocalDevVPN из App Store.
3. На iPhone: «Настройки → Основные → VPN и управление устройством» — доверять разработчику со своим Apple ID; «Настройки → Конфиденциальность и безопасность → Режим разработчика» — включить (iPhone перезагрузится).
4. Подключите LocalDevVPN, войдите в SideStore тем же Apple ID и сразу обновите сам SideStore (My Apps → счётчик «7 DAYS»).

LocalDevVPN должен быть подключён при каждой установке, обновлении и продлении приложений.

### «Траты»

- **Файлом.** Передайте `.ipa` на iPhone через AirDrop или «Файлы», затем в SideStore: My Apps → «+» → выберите файл.
- **Через source.** SideStore → Sources → «+» → `https://raw.githubusercontent.com/skxfn/expenses-tracker/main/source.json` (или ссылка `sidestore://source?url=<этот URL>`). Новые версии появятся в обновлениях SideStore. Репозиторий и релизы должны быть публичными — по raw-ссылке приватного репозитория SideStore ничего не скачает.

### Продление подписи ночью

Подпись бесплатного Apple ID живёт 7 дней. SideStore продлевает её в фоне, надёжнее добавить автоматизацию в «Командах»: Автоматизация → «+» → «Время суток» (ночью, ежедневно) → действие «Refresh All Apps» из SideStore → выключить «Спрашивать до запуска». На ночь оставляйте LocalDevVPN подключённым и iPhone в Wi-Fi.

## Ограничения бесплатного Apple ID

- Не больше 3 приложений одновременно (включая сам SideStore) и не больше 10 App ID за 7 дней.
- Без продления раз в 7 дней приложение перестаёт запускаться (после продления снова работает).
- Нет push-уведомлений, iCloud/CloudKit, App Groups, Sign in with Apple, Apple Pay, Associated Domains — `build_ipa.sh` не соберёт `.ipa` с такими entitlements.
- SideStore может дописать к Bundle ID суффикс Team ID (`com.skxfn.expenses.ABCDE12345`), поэтому в коде ничего не завязано на точный Bundle ID: берите `Bundle.main.bundleIdentifier`.

## Резервные копии

Данные хранятся только на iPhone, iCloud-синхронизации нет. Они теряются при удалении приложения, а смена Apple ID меняет Team ID, а с ним и суффикс Bundle ID — получится новое пустое приложение. Регулярно делайте экспорт резервной копии в приложении и сохраняйте файл вне iPhone (компьютер, облако).

## Структура

```
App/                      UI на SwiftUI, ресурсы
Packages/ExpenseCore/     логика и модель данных (SwiftData), тесты
Config/Version.xcconfig   версия приложения
project.yml               описание проекта для XcodeGen; Expenses.xcodeproj закоммичен
scripts/                  build_ipa.sh, bump_version.sh, update_source.py
source.json               source для SideStore/AltStore
.github/workflows/        release.yml — сборка и публикация по тегу
```

После правки `project.yml`: `xcodegen generate`.
