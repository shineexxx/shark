#!/bin/bash
# Собирает Shark.app: SPM-сборка + иконка + упаковка в бандл + вкладывание движков.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP="$ROOT/build/Shark.app"
CONTENTS="$APP/Contents"

say() { printf "\033[1;36m==>\033[0m %s\n" "$1"; }

# 1. Движки. fetch-tools.sh идемпотентен: докачивает только недостающее.
for tool in ffmpeg ffprobe yt-dlp deno; do
  if [ ! -x "$ROOT/Tools/$tool" ]; then
    [ "$tool" = "deno" ] && [ "${SKIP_DENO:-0}" = "1" ] && continue
    say "Не хватает $tool — запускаю fetch-tools.sh"
    bash "$ROOT/Scripts/fetch-tools.sh"
    break
  fi
done

# 2. Сборка
say "Компилирую ($CONFIG)"
swift build -c "$CONFIG" --arch "$(uname -m)"
BIN="$(swift build -c "$CONFIG" --arch "$(uname -m)" --show-bin-path)/Shark"

# 3. Бандл
say "Собираю Shark.app"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/Tools"

cp "$BIN" "$CONTENTS/MacOS/Shark"

# CLI — тот же бинарник под другим именем: он смотрит на имя вызова и уходит
# в терминальный режим, поэтому отдельной сборки и дублирования кода нет.
# Лежит в Helpers, а не рядом в MacOS: файловая система macOS регистро-
# независима, и ссылка `shark` затёрла бы сам `Shark`.
mkdir -p "$CONTENTS/Helpers"
ln -sf ../MacOS/Shark "$CONTENTS/Helpers/shark"

# Страница руководства лежит в бандле по стандартной раскладке man,
# поэтому её можно и показать напрямую (`shark man`), и подключить
# в системный путь одной ссылкой.
mkdir -p "$CONTENTS/Resources/man/man1"
cp "$ROOT/Resources/shark.1" "$CONTENTS/Resources/man/man1/shark.1"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# Пустых .lproj достаточно, чтобы AppKit перевёл стандартные меню:
# он смотрит на набор каталогов, а не на их содержимое.
for lang in en ru; do
  mkdir -p "$CONTENTS/Resources/$lang.lproj"
  : > "$CONTENTS/Resources/$lang.lproj/Localizable.strings"
done

# Заголовки пунктов в контекстном меню Finder система берёт из отдельного
# ServicesMenu.strings, а не из нашей таблицы переводов и не из Localizable:
# меню рисует Finder, и до нашего кода дело ещё не дошло. Так же это сделано
# у Safari. Язык здесь системный — настройку языка внутри приложения Finder
# не видит и видеть не может.
printf '"Convert with Shark" = "Конвертировать через Shark";\n' \
  > "$CONTENTS/Resources/ru.lproj/ServicesMenu.strings"
printf 'APPL????' > "$CONTENTS/PkgInfo"

for tool in ffmpeg ffprobe yt-dlp deno; do
  if [ -f "$ROOT/Tools/$tool" ]; then
    cp "$ROOT/Tools/$tool" "$CONTENTS/Resources/Tools/$tool"
    chmod +x "$CONTENTS/Resources/Tools/$tool"
  else
    echo "предупреждение: $tool отсутствует, приложение будет искать его в системе" >&2
  fi
done

# Иконку рисует само приложение — та же геометрия, что у логотипа в шапке.
say "Рисую иконку"
"$BIN" --make-icon "$ROOT/Resources/AppIcon.icns" >/dev/null 2>&1 \
  && cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns" \
  || echo "предупреждение: не удалось собрать иконку" >&2

# 4. Подпись (ad-hoc — достаточно для запуска на своей машине)
say "Подписываю"
for tool in "$CONTENTS/Resources/Tools/"*; do
  [ -f "$tool" ] || continue
  codesign --force --sign - --timestamp=none "$tool" >/dev/null 2>&1 || true
done
codesign --force --deep --sign - --timestamp=none \
  --entitlements "$ROOT/Resources/Shark.entitlements" "$APP" >/dev/null 2>&1 \
  || codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

xattr -cr "$APP" 2>/dev/null || true

# 5. Установка в /Applications — по флагу, чтобы обычная сборка ничего не трогала
if [ "${INSTALL:-0}" = "1" ]; then
  TARGET="/Applications/Shark.app"
  say "Устанавливаю в $TARGET"
  # Работающую копию сначала останавливаем, иначе замена оставит смесь старого и нового.
  pkill -f "$TARGET/Contents/MacOS/Shark" 2>/dev/null || true
  rm -rf "$TARGET"
  cp -R "$APP" "$TARGET"
  xattr -cr "$TARGET" 2>/dev/null || true
  say "Установлено: $TARGET"
  say "Запуск:  open \"$TARGET\""
else
  say "Готово: $APP"
  say "Запуск:  open \"$APP\""
  say "Установка в /Applications:  INSTALL=1 bash Scripts/build.sh"
fi
