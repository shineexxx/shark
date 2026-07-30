#!/bin/bash
# Скачивает автономные бинарники ffmpeg / ffprobe / yt-dlp в Tools/.
# Нужен только на машине сборки — готовый .app уже несёт их внутри.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/Tools"
mkdir -p "$TOOLS"

ARCH="$(uname -m)"   # arm64 | x86_64

say() { printf "\033[1;36m==>\033[0m %s\n" "$1"; }

# --- yt-dlp -------------------------------------------------------------
if [ ! -x "$TOOLS/yt-dlp" ]; then
  say "Скачиваю yt-dlp (macOS standalone)"
  curl -fL --progress-bar \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" \
    -o "$TOOLS/yt-dlp"
  chmod +x "$TOOLS/yt-dlp"
else
  say "yt-dlp уже на месте"
fi

# --- ffmpeg / ffprobe ---------------------------------------------------
fetch_ff() {
  local name="$1"
  if [ -x "$TOOLS/$name" ]; then say "$name уже на месте"; return; fi

  say "Скачиваю $name ($ARCH)"
  local tmp
  tmp="$(mktemp -d)"

  # Статические сборки без внешних зависимостей.
  local url="https://github.com/eugeneware/ffmpeg-static/releases/latest/download/${name}-darwin-${ARCH}"
  if curl -fL --progress-bar "$url" -o "$tmp/$name"; then
    mv "$tmp/$name" "$TOOLS/$name"
    chmod +x "$TOOLS/$name"
  else
    echo "Не удалось скачать $name с $url" >&2
    echo "Положите бинарник вручную в $TOOLS/$name" >&2
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp"
}

fetch_ff ffmpeg
fetch_ff ffprobe

# --- deno ---------------------------------------------------------------
# yt-dlp требует JS-рантайм для YouTube. Без него остальные площадки работают,
# а YouTube отдаёт неполный список форматов.
if [ "${SKIP_DENO:-0}" = "1" ]; then
  say "deno пропущен (SKIP_DENO=1) — YouTube будет работать частично"
elif [ ! -x "$TOOLS/deno" ]; then
  say "Скачиваю deno (JS-рантайм для YouTube)"
  case "$ARCH" in
    arm64)  DENO_ASSET="deno-aarch64-apple-darwin.zip" ;;
    x86_64) DENO_ASSET="deno-x86_64-apple-darwin.zip" ;;
    *) echo "неизвестная архитектура $ARCH" >&2; DENO_ASSET="" ;;
  esac
  if [ -n "$DENO_ASSET" ]; then
    tmp="$(mktemp -d)"
    if curl -fL --progress-bar \
        "https://github.com/denoland/deno/releases/latest/download/$DENO_ASSET" \
        -o "$tmp/deno.zip"; then
      unzip -qo "$tmp/deno.zip" -d "$tmp"
      mv "$tmp/deno" "$TOOLS/deno"
      chmod +x "$TOOLS/deno"
    else
      echo "не удалось скачать deno — YouTube будет работать частично" >&2
    fi
    rm -rf "$tmp"
  fi
else
  say "deno уже на месте"
fi

# --- Проверка -----------------------------------------------------------
say "Снимаю карантин и подписываю ad-hoc"
for tool in ffmpeg ffprobe yt-dlp deno; do
  [ -f "$TOOLS/$tool" ] || continue
  xattr -dr com.apple.quarantine "$TOOLS/$tool" 2>/dev/null || true
  codesign --force --sign - "$TOOLS/$tool" 2>/dev/null || true
done

say "Проверяю"
"$TOOLS/ffmpeg"  -version | head -1
"$TOOLS/ffprobe" -version | head -1
"$TOOLS/yt-dlp"  --version
[ -x "$TOOLS/deno" ] && "$TOOLS/deno" --version | head -1

say "Готово: $TOOLS"
