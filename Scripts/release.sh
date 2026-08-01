#!/bin/bash
# Собирает Shark.app, пакует в zip и публикует релиз на GitHub.
# Из этого архива Homebrew-каск и ставит приложение.
#
#   bash Scripts/release.sh 1.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Использование: bash Scripts/release.sh <версия>   например 1.0" >&2
  exit 2
fi
TAG="v$VERSION"

say() { printf "\033[1;36m==>\033[0m %s\n" "$1"; }

# 1. Версия в бандле должна совпадать с тегом, иначе каск и приложение разойдутся.
say "Проставляю версию $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$ROOT/Resources/Info.plist"

# 2. Чистая сборка
say "Собираю"
rm -rf "$ROOT/build"
bash "$ROOT/Scripts/build.sh" >/dev/null

# 3. Архив. ditto сохраняет символические ссылки и права — обычный zip их портит,
#    а внутри бандла ссылкой сделан весь CLI.
say "Пакую"
ARCHIVE="$ROOT/build/Shark-$VERSION.zip"
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/Shark.app" "$ARCHIVE"

SHA="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
SIZE="$(du -h "$ARCHIVE" | cut -f1)"
say "Готово: $(basename "$ARCHIVE"), $SIZE"
say "sha256: $SHA"

# 4. Релиз
say "Публикую релиз $TAG"
gh release create "$TAG" "$ARCHIVE" \
  --title "Shark $VERSION" \
  --notes "Native macOS file converter and video downloader.

Install:

    brew tap shineexxx/tap
    brew install --cask shark

The bundle carries ffmpeg, ffprobe, yt-dlp and deno inside, so nothing else
has to be installed. The \`shark\` command and its manual page are linked
automatically." \
  2>&1 | tail -2

say "Обновите каск: sha256 $SHA"
