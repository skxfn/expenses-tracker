#!/usr/bin/env bash
# Поднимает версию в Config/Version.xcconfig:
#   MARKETING_VERSION X.Y.Z  -> по умолчанию patch +1 (minor/major — по аргументу)
#   CURRENT_PROJECT_VERSION  -> всегда +1
# Использование: scripts/bump_version.sh [patch|minor|major]
set -euo pipefail

die() { echo "Ошибка: $*" >&2; exit 1; }

FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Config/Version.xcconfig"
PART="${1:-patch}"

[[ -f "$FILE" ]] || die "не найден $FILE"

read_setting() {
    sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p" "$FILE" | head -n 1
}

version="$(read_setting MARKETING_VERSION)"
build="$(read_setting CURRENT_PROJECT_VERSION)"

[[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
    || die "MARKETING_VERSION в $FILE должен быть вида X.Y.Z, сейчас: '$version'"
major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"; patch="${BASH_REMATCH[3]}"
[[ "$build" =~ ^[0-9]+$ ]] \
    || die "CURRENT_PROJECT_VERSION в $FILE должен быть целым числом, сейчас: '$build'"

case "$PART" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *) die "неизвестная часть версии '$PART' (patch|minor|major)" ;;
esac

new_version="$major.$minor.$patch"
new_build=$((build + 1))

sed -i '' -E \
    -e "s/^([[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*).*/\1$new_version/" \
    -e "s/^([[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*).*/\1$new_build/" \
    "$FILE"

echo "Версия: $version ($build) -> $new_version ($new_build)"
