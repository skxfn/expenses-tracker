#!/usr/bin/env python3
"""Добавляет версию из собранного .ipa в source.json (формат AltStore/SideStore source).

Использование:
    python3 scripts/update_source.py dist/Expenses-1.0.1.ipa [--tag v1.0.1] [--notes "Что нового"]

Из Info.plist внутри .ipa берутся версия, build, bundle ID, минимальная iOS и privacy-ключи
(NS…UsageDescription), из файла — размер и sha256: SideStore сверяет их с загруженным .ipa.
downloadURL указывает на ассет GitHub Release: https://github.com/<repo>/releases/download/<tag>/<файл>.

Скрипт перезаписывает только то, что выводится из .ipa и имени репозитория (versions, appPermissions,
iconURL, website, sourceURL и дублирующие поля последней версии для старых клиентов);
остальные поля source.json (названия, описания) правятся вручную.
"""
import argparse
import hashlib
import json
import os
import plistlib
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

# Единственное место с именем GitHub-репозитория. В GitHub Actions его заменяет $GITHUB_REPOSITORY.
DEFAULT_REPO = "skxfn/expenses-tracker"
DEFAULT_BRANCH = "main"

ROOT = Path(__file__).resolve().parent.parent
APP_ICON_SET = "App/Resources/Assets.xcassets/AppIcon.appiconset"
INFO_PLIST = re.compile(r"^Payload/[^/]+\.app/Info\.plist$")
PRIVACY_KEY = re.compile(r"^NS\w*UsageDescription$")


def fail(message):
    sys.exit(f"Ошибка: {message}")


def read_info_plist(ipa):
    try:
        with zipfile.ZipFile(ipa) as archive:
            names = [n for n in archive.namelist() if INFO_PLIST.match(n)]
            if len(names) != 1:
                fail(f"в {ipa} ожидался ровно один Payload/*.app/Info.plist, найдено: {len(names)}")
            return plistlib.loads(archive.read(names[0]))
    except zipfile.BadZipFile:
        fail(f"{ipa} — не zip-архив (.ipa)")


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def icon_url(repo, branch):
    """Raw-ссылка на иконку 1024×1024 из AppIcon.appiconset; если её нет — аватар владельца репо."""
    contents = ROOT / APP_ICON_SET / "Contents.json"
    try:
        images = json.loads(contents.read_text(encoding="utf-8")).get("images", [])
    except (OSError, ValueError):
        images = []
    for image in images:
        filename = image.get("filename")
        if filename and (ROOT / APP_ICON_SET / filename).is_file():
            return f"https://raw.githubusercontent.com/{repo}/{branch}/{quote(f'{APP_ICON_SET}/{filename}')}"
    owner = repo.split("/")[0]
    print(f"Предупреждение: в {APP_ICON_SET} нет файла иконки — iconURL указывает на аватар {owner}.",
          file=sys.stderr)
    return f"https://github.com/{owner}.png"


def main():
    parser = argparse.ArgumentParser(description="Добавить версию из .ipa в source.json")
    parser.add_argument("ipa", type=Path, help="путь к собранному .ipa")
    parser.add_argument("--tag", help="тег GitHub Release (по умолчанию v<версия>)")
    parser.add_argument("--notes", help="описание версии (что нового)")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY") or DEFAULT_REPO,
                        help=f"owner/name репозитория (по умолчанию $GITHUB_REPOSITORY или {DEFAULT_REPO})")
    parser.add_argument("--branch", default=DEFAULT_BRANCH,
                        help=f"ветка, где лежит source.json (по умолчанию {DEFAULT_BRANCH})")
    parser.add_argument("--source", type=Path, default=ROOT / "source.json", help="путь к source.json")
    args = parser.parse_args()

    if not args.ipa.is_file():
        fail(f"не найден {args.ipa}")
    if not args.source.is_file():
        fail(f"не найден {args.source}")
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", args.repo):
        fail(f"--repo должен быть вида owner/name, сейчас: '{args.repo}'")

    info = read_info_plist(args.ipa)
    try:
        bundle_id = info["CFBundleIdentifier"]
        version = info["CFBundleShortVersionString"]
        build = info["CFBundleVersion"]
        min_os = info["MinimumOSVersion"]
    except KeyError as error:
        fail(f"в Info.plist нет ключа {error}")

    tag = args.tag or f"v{version}"
    download_url = (f"https://github.com/{args.repo}/releases/download/"
                    f"{quote(tag)}/{quote(args.ipa.name)}")
    new_version = {
        "version": version,
        "buildVersion": build,
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": args.notes or f"Версия {version} (сборка {build})",
        "downloadURL": download_url,
        "size": args.ipa.stat().st_size,
        "sha256": sha256_of(args.ipa),
        "minOSVersion": min_os,
    }

    try:
        source = json.loads(args.source.read_text(encoding="utf-8"))
    except ValueError as error:
        fail(f"{args.source} — некорректный JSON: {error}")
    app = next((a for a in source.get("apps", []) if a.get("bundleIdentifier") == bundle_id), None)
    if app is None:
        fail(f"в {args.source.name} нет приложения с bundleIdentifier '{bundle_id}'")

    source["website"] = f"https://github.com/{args.repo}"
    source["sourceURL"] = f"https://raw.githubusercontent.com/{args.repo}/{args.branch}/source.json"
    app["iconURL"] = icon_url(args.repo, args.branch)
    # Сборка без подписи: в бинарнике нет entitlements (build_ipa.sh это проверяет).
    # Privacy-ключи должны совпадать с Info.plist, иначе SideStore откажется ставить.
    app["appPermissions"] = {
        "entitlements": [],
        "privacy": {key: value for key, value in sorted(info.items()) if PRIVACY_KEY.match(key)},
    }
    # Новая версия — первой (SideStore считает первую последней); повтор той же версии заменяется.
    app["versions"] = [new_version] + [v for v in app.get("versions", []) if v.get("version") != version]
    # Дубли последней версии на уровне приложения — для старых клиентов AltStore/SideStore.
    app["version"] = version
    app["versionDate"] = new_version["date"]
    app["versionDescription"] = new_version["localizedDescription"]
    app["downloadURL"] = download_url
    app["size"] = new_version["size"]

    args.source.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{args.source.name}: {bundle_id} {version} (build {build}), {new_version['size']} байт")
    print(f"downloadURL: {download_url}")


if __name__ == "__main__":
    main()
