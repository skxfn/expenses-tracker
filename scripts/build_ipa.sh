#!/usr/bin/env bash
# Собирает неподписанный dist/Expenses-<версия>.ipa для установки через SideStore/AltStore.
# Подпись делает сам SideStore (бесплатным Apple ID), поэтому здесь она выключена.
#
# Использование: scripts/build_ipa.sh [--no-bump]
#   по умолчанию поднимает версию (patch +1, build +1) в Config/Version.xcconfig,
#   чтобы SideStore увидел обновление; --no-bump — собрать текущую версию (CI, пересборка).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Expenses.xcodeproj"
SCHEME="Expenses"
TARGET="Expenses"
PRODUCT="Expenses"
VERSION_FILE="$ROOT/Config/Version.xcconfig"
BUILD_DIR="$ROOT/build"
DIST_DIR="$ROOT/dist"
ARCHIVE="$BUILD_DIR/$PRODUCT.xcarchive"
STAGE="$BUILD_DIR/ipa"
LOG="$BUILD_DIR/xcodebuild.log"
VERSION_BACKUP="$BUILD_DIR/Version.xcconfig.bak"

die() { echo "Ошибка: $*" >&2; exit 1; }

usage() { sed -n '2,7s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"; }

BUMP=1
for arg in "$@"; do
    case "$arg" in
        --no-bump) BUMP=0 ;;
        -h|--help) usage; exit 0 ;;
        *) die "неизвестный аргумент '$arg' (см. --help)" ;;
    esac
done

command -v xcodebuild >/dev/null || die "xcodebuild не найден — нужен Xcode"
[[ -d "$PROJECT" ]] || die "не найден $PROJECT"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# Если сборка упадёт после поднятия версии — вернуть версию обратно, чтобы не пропускать номера.
BUMPED=0
restore_version_on_failure() {
    local status=$?
    if (( status != 0 && BUMPED )); then
        cp "$VERSION_BACKUP" "$VERSION_FILE"
        echo "Сборка не удалась — Config/Version.xcconfig возвращён к прежней версии." >&2
    fi
}
trap restore_version_on_failure EXIT

# Entitlements, которые бесплатный Apple ID (SideStore) выдать не может.
FORBIDDEN_FOUND=()
check_entitlements() {
    local file="$1" origin="$2" key what
    plutil -lint "$file" >/dev/null || die "не удалось прочитать entitlements: $file"
    while IFS= read -r key; do
        case "$key" in
            aps-environment) what="Push Notifications (APNs)" ;;
            com.apple.developer.icloud-*|com.apple.developer.ubiquity-*) what="iCloud / CloudKit" ;;
            com.apple.security.application-groups) what="App Groups" ;;
            com.apple.developer.applesignin) what="Sign in with Apple" ;;
            com.apple.developer.in-app-payments) what="Apple Pay" ;;
            com.apple.developer.associated-domains) what="Associated Domains" ;;
            *) continue ;;
        esac
        FORBIDDEN_FOUND+=("$key ($what) — $origin")
    done < <(plutil -convert xml1 -o - "$file" | sed -n -E 's/.*<key>([^<]+)<\/key>.*/\1/p')
}

fail_if_forbidden() {
    (( ${#FORBIDDEN_FOUND[@]} == 0 )) && return 0
    echo "Ошибка: найдены entitlements, недоступные бесплатному Apple ID:" >&2
    printf '  - %s\n' "${FORBIDDEN_FOUND[@]}" >&2
    echo "SideStore их не выдаст, и эти функции не заработают. Уберите capabilities из проекта (project.yml / .entitlements)." >&2
    exit 1
}

# 1. Версия
if (( BUMP )); then
    cp "$VERSION_FILE" "$VERSION_BACKUP"
    BUMPED=1
    "$ROOT/scripts/bump_version.sh"
fi

# 2. Entitlements, объявленные в проекте. Без подписи Xcode не встраивает их в .app,
#    а значит SideStore их не выдаст и фича молча не заработает — поэтому проверяем заранее.
echo "Проверка entitlements проекта…"
SETTINGS="$BUILD_DIR/build-settings.txt"
if ! xcodebuild -project "$PROJECT" -target "$TARGET" -configuration Release -showBuildSettings \
        > "$SETTINGS" 2>&1; then
    tail -n 5 "$SETTINGS" >&2
    die "не удалось прочитать настройки сборки (xcodebuild -showBuildSettings)"
fi
entitlements_path="$(sed -n -E 's/^ *CODE_SIGN_ENTITLEMENTS = (.+)$/\1/p' "$SETTINGS" | head -n 1)"
if [[ -n "$entitlements_path" ]]; then
    [[ "$entitlements_path" == /* ]] || entitlements_path="$ROOT/$entitlements_path"
    [[ -f "$entitlements_path" ]] || die "CODE_SIGN_ENTITLEMENTS указывает на несуществующий файл: $entitlements_path"
    check_entitlements "$entitlements_path" "CODE_SIGN_ENTITLEMENTS: ${entitlements_path#"$ROOT/"}"
fi
fail_if_forbidden

# 3. Архив без подписи
echo "Сборка архива (Release, generic/platform=iOS)… Лог: $LOG"
rm -rf "$ARCHIVE"
if ! xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        -archivePath "$ARCHIVE" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        > "$LOG" 2>&1; then
    grep -E ' error: |^error: ' "$LOG" | sort -u | tail -n 20 >&2 || true
    tail -n 15 "$LOG" >&2
    if grep -q 'is not installed' "$LOG"; then
        echo "Подсказка: не установлена платформа iOS для Xcode — Xcode > Settings > Components или 'xcodebuild -downloadPlatform iOS'." >&2
    fi
    die "xcodebuild archive завершился с ошибкой, полный лог: $LOG"
fi

APP="$ARCHIVE/Products/Applications/$PRODUCT.app"
[[ -d "$APP" ]] || die "в архиве нет $PRODUCT.app: $APP"

# 4. Entitlements, встроенные в сам .app (появляются, только если бинарник подписан)
if codesign -d --entitlements - --xml "$APP" > "$BUILD_DIR/embedded.entitlements" 2>/dev/null \
        && [[ -s "$BUILD_DIR/embedded.entitlements" ]]; then
    check_entitlements "$BUILD_DIR/embedded.entitlements" "$PRODUCT.app"
fi
fail_if_forbidden

# 5. Упаковка в .ipa (Payload/<App>.app в zip)
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Info.plist")"
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw -o - "$APP/Info.plist")"
IPA="$DIST_DIR/$PRODUCT-$VERSION.ipa"

rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/$PRODUCT.app"
rm -f "$IPA"  # zip дописывает в существующий архив, поэтому удаляем старый
(cd "$STAGE" && zip -q -r -y -X "$IPA" Payload)
rm -rf "$STAGE"

BYTES="$(stat -f %z "$IPA")"
echo
echo "Готово: $IPA"
echo "Размер: $BYTES байт ($(awk -v b="$BYTES" 'BEGIN { printf "%.2f", b / 1048576 }') МБ)"
echo "Версия: $VERSION (build $BUILD_NUMBER)"
if (( BUMPED )); then
    echo "Не забудьте закоммитить Config/Version.xcconfig."
fi
