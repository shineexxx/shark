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

# 3b. DMG с оформленным окном: фон, стрелка и подпись «Drag to Applications».
#     Образ сначала собирается перезаписываемым — расставить значки и назначить
#     фон можно только в смонтированном томе, через Finder.
say "Собираю образ"
DMG="$ROOT/build/Shark-$VERSION.dmg"
RW="$ROOT/build/Shark-rw.dmg"
STAGE="$(mktemp -d)/Shark"
mkdir -p "$STAGE/.background"
# ditto, а не cp: внутри бандла есть символические ссылки.
ditto "$ROOT/build/Shark.app" "$STAGE/Shark.app"
ln -s /Applications "$STAGE/Applications"

# Фон рисует само приложение — тем же кодом, что иконку.
"$ROOT/build/Shark.app/Contents/MacOS/Shark" --make-dmg-background "$STAGE/.background" >/dev/null
# Retina-вариант вкладывается в один tiff: Finder сам выберет нужный.
tiffutil -cathidpicheck "$STAGE/.background/background.png" \
                        "$STAGE/.background/background@2x.png" \
                        -out "$STAGE/.background/background.tiff" >/dev/null 2>&1
rm -f "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png"

# Старое монтирование заняло бы имя тома, и образ смонтировался бы как
# «Shark 1» — тогда оформление применилось бы не туда.
for stale in /Volumes/Shark /Volumes/Shark\ *; do
  [ -d "$stale" ] && hdiutil detach "$stale" -force >/dev/null 2>&1 || true
done

rm -f "$RW" "$DMG"
hdiutil create -volname "Shark" -srcfolder "$STAGE" -ov \
  -format UDRW -fs HFS+ "$RW" >/dev/null
rm -rf "$(dirname "$STAGE")"

MOUNT="$(hdiutil attach "$RW" -nobrowse -noautoopen | grep '/Volumes' | sed 's|.*\(/Volumes.*\)|\1|')"
say "Оформляю окно"
VOLUME="$(basename "$MOUNT")"
osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "предупреждение: не удалось оформить окно (нужен доступ к Finder)" >&2
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 1000, 640}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Shark.app" of container window to {220, 250}
    set position of item "Applications" of container window to {580, 250}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach "$MOUNT" >/dev/null

say "Сжимаю образ"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"

SHA="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
DMG_SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
SIZE="$(du -h "$ARCHIVE" | cut -f1)"
say "Готово: $(basename "$ARCHIVE"), $SIZE"
say "zip  sha256: $SHA"
say "dmg  sha256: $DMG_SHA  ($(du -h "$DMG" | cut -f1))"

# 4. Релиз
say "Публикую релиз $TAG"
gh release create "$TAG" "$ARCHIVE" "$DMG" \
  --title "Shark $VERSION" \
  --notes "Native macOS file converter and video downloader.

Install:

    brew tap shineexxx/tap
    brew install --cask shark

The bundle carries ffmpeg, ffprobe, yt-dlp and deno inside, so nothing else
has to be installed. The \`shark\` command and its manual page are linked
automatically." \
  2>&1 | tail -2

say "Обновите каск: sha256 $DMG_SHA"
