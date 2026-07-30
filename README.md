# Shark

A native macOS file converter and video downloader, written in SwiftUI with a Liquid Glass interface.

Everything runs locally. The finished `.app` carries its engines inside — no ffmpeg, no Python, no Homebrew required on the machine that runs it.

## Build

```bash
bash Scripts/build.sh
```

The script fetches the engines (first build only), compiles, draws the icon and assembles `build/Shark.app`.

```bash
open build/Shark.app
```

To install straight into `/Applications`:

```bash
INSTALL=1 bash Scripts/build.sh
```

Quick run without bundling: `swift run`.

**Requirements:** Swift 6 — Command Line Tools are enough, Xcode is not needed.

## Converting

| Category | Engine | Formats |
|---|---|---|
| Audio | ffmpeg | mp3, m4a, aac, wav, flac, alac, ogg, opus, wma, aiff, ac3, amr, caf, mp2 |
| Video | ffmpeg | mp4, mkv, mov, webm, avi, m4v, flv, wmv, mpg, ts, ogv, 3gp, ProRes, gif |
| Images | ImageIO, ffmpeg as fallback | jpg, png, heic, webp, tiff, gif, bmp, avif, jp2, ico, tga, ppm — plus RAW and psd on input |
| Documents | NSAttributedString, PDFKit, CoreText | pdf, docx, rtf, html, txt, md |

Routing is automatic: the engine is chosen from the pair of input and output formats.

Notable routes:

- images → **pdf** (PDFKit);
- **pdf** → png/jpg/tiff, page by page — a multi-page PDF yields `name-01.png`, `name-02.png`, …;
- **pdf** → txt / rtf / html;
- doc, docx, odt, rtf, html, md, txt → pdf / docx / rtf / html / txt / md;
- video → gif with palette generation, so gradients stay clean.

Settings: video quality (CRF preset), resolution cap, audio bitrate, JPEG/HEIC quality, metadata stripping, output folder, per-file output name.

`.ico` is written by hand rather than by an engine. ImageIO does not list `com.microsoft.ico` among the types it can write, and the ffmpeg ICO muxer only accepts a narrow set of sizes and pixel formats — it fails on an ordinary JPEG. The built-in writer embeds a full set of sizes (16 … 256) as PNG payloads, which is what Windows expects.

`.docx` output is produced by a minimal OOXML writer (paragraphs, bold, italic, underline, font size) packed with the system `/usr/bin/zip`. Rich formatting from the source is simplified — a deliberate trade for not depending on Word or LibreOffice.

### Where files can be dropped

- **Into the window** — the left panel of the converter.
- **Onto the Dock icon** — files join the queue of the window that is already open. The scene is declared as `Window`, not `WindowGroup`: a group spawned a new window for every file opened, so dropping onto the Dock kept multiplying windows.
- **Onto the menu bar icon** — the fin next to the clock. Click opens the window, Control-click opens a menu.

`Info.plist` declares the document type as `public.item`, the root of the type hierarchy, so any file or folder is accepted. The handler rank is `Alternate` so Shark never steals files from the apps that normally own them.

If the menu bar icon is not visible, a menu bar manager (Ice, Bartender and friends) is hiding it, or the notch pushed it off. The item is created and working either way; it has an `autosaveName`, so once dragged into place with Cmd held, its position sticks.

## Downloading

The engine is yt-dlp, which ships extractors for a very large number of sites — YouTube, RuTube, VK Video, TikTok and many others. Shark contains no per-site code; every link goes through the same call.

- Video capped at 480p … 2160p or "best", in mp4 / mkv / webm.
- Audio only: mp3, m4a, opus, flac, wav.
- Whole playlists, embedded cover art, ru/en subtitles.
- Cookies from Safari, Chrome, Firefox or Edge, or a `cookies.txt` file.
- Paste one link or a list, one per line. Title and duration are resolved automatically.

### Link checking

Paste a link and, after a 700 ms debounce, a status line appears under the field: the platform, the video title and its duration — or the reason it will not work. The check uses the same cookies and the same JS runtime as the real download, otherwise it would report failures that downloading would not hit.

The lookup is not wasted: if you press **Add** the result is reused, so the queue is filled without a second network round trip. If you press **Add** while the check is still running, the check is handed over to the queue row and finishes there instead of being cancelled and restarted.

### Notes from testing against live platforms

| Platform | State |
|---|---|
| RuTube | works out of the box |
| VK Video | works out of the box, serves up to 1080p |
| YouTube | needs cookies — anonymous requests get "Sign in to confirm you're not a bot" |
| TikTok | IP-dependent; some addresses are refused with "Your IP address is blocked" |

Both limits are platform policy, not app behaviour.

YouTube also needs a JavaScript runtime: stream URLs are delivered encrypted and yt-dlp has to execute the site's own JS to decipher them. Shark bundles `deno` for this. Without it part of the formats stay invisible. This is the single reason the bundle is ~200 MB instead of ~70 MB.

**Safari cookies require Full Disk Access** — the cookie file lives in a protected container and macOS refuses to read it otherwise. The app detects that specific failure and offers a button straight to the right settings pane. Firefox needs no permission at all, and a `cookies.txt` file avoids the question entirely.

Only download what you have the right to: your own uploads, freely licensed material, or content the rights holder permits you to download. The terms of each platform are your responsibility.

## Command line

`shark` ships inside the app — the same engines, from a terminal.

```bash
sudo ln -sf /Applications/Shark.app/Contents/Helpers/shark /usr/local/bin/shark
```

```bash
shark convert clip.mov --to mp4 --quality high
shark convert *.heic --to jpg --image-quality 90 --out ~/Pictures
shark convert doc.docx --to pdf --name report
shark download <url> --quality 1080
shark download <url> --audio mp3 --cookies firefox
shark formats
shark info clip.mov
shark help
```

Result paths go to stdout, progress goes to stderr, so `shark convert *.wav --to mp3 > done.txt` yields a clean list of paths ready for further processing. The progress bar is drawn only when stderr is a terminal.

Exit codes: `0` success, `1` some files failed, `2` bad arguments, `3` a required engine is missing. Unknown options are rejected rather than silently ignored — a typo in a flag is an error, not a silent change in behaviour.

There is no separate CLI build. It is the same binary invoked under the name `shark`; it picks the mode from its own name and the first argument. Conversion in the terminal and in the window therefore cannot drift apart — the code is literally the same.

The symlink lives in `Contents/Helpers` rather than next to `Shark` in `Contents/MacOS`: the macOS filesystem is case-insensitive, so a file named `shark` would overwrite `Shark`.

## Settings

**General** — interface language (System / English / Русский), launch at login, keep running when the window is closed, menu bar icon.

Closing the window with the red button drops the app out of the Dock and leaves it in the menu bar; while a window is open the Dock icon is always present. Background mode forces the menu bar icon on — an app with no window and no icon would be unreachable.

**Conversion** — default output folder, default video quality and audio bitrate, metadata stripping, overwrite behaviour, reveal in Finder / sound / notification when the queue finishes.

**Downloads** — default download folder.

**Engines** — status and versions of ffmpeg, ffprobe, yt-dlp and deno, plus a one-click yt-dlp update.

### Updating engines

Sites keep changing, so yt-dlp goes stale faster than everything else. The **Update yt-dlp** button downloads the current release into Application Support rather than into the bundle: editing bundle contents breaks its signature, and the update would be lost on every reinstall.

Engine lookup therefore checks Application Support **first**, treating the bundled binary as the baseline that an update overrides. The download is staged, de-quarantined, ad-hoc signed and executed once before it replaces anything — a truncated download must not leave the app without a working yt-dlp. A **Revert** button restores the bundled version.

## Localisation

The interface ships in English and Russian and follows the system language unless told otherwise.

Translations live in a Swift table keyed by the English string itself, so an untranslated string degrades into meaningful English rather than into an identifier. Standard menus (File, Edit, Window, Help) are drawn by AppKit, which needs `en.lproj` and `ru.lproj` present in the bundle and `CFBundleLocalizations` declared — the build script creates both.

Changing the language in Settings rebuilds the interface immediately; the system menu titles follow after a restart, since AppKit reads them once at launch.

## Project layout

```
Sources/Shark/
├── SharkApp.swift              entry point, window, menu commands
├── main.swift                  routes GUI / CLI / selftest / icon modes
├── Core/
│   ├── ProcessRunner.swift     runs ffmpeg and yt-dlp, streams output line by line
│   ├── Tools.swift             engine lookup: updates → bundle → system
│   ├── DownloadRequest.swift   shared yt-dlp argument building for window and CLI
│   ├── EngineUpdater.swift     yt-dlp updates without a rebuild
│   ├── AppSettings.swift       single source of truth for settings
│   ├── Localization.swift      language selection and the translation table
│   ├── IconFactory.swift       draws AppIcon.icns from the same geometry as the logo
│   ├── SelfTest.swift          headless engine verification
│   └── Formats.swift           format catalogue and file type detection
├── Convert/
│   ├── ConversionEngine.swift  picks an engine for the input/output pair
│   ├── FFmpegConverter.swift   audio, video, exotic image formats
│   ├── ImageConverter.swift    ImageIO
│   ├── IcoWriter.swift         hand-written multi-size .ico
│   ├── DocumentConverter.swift PDFKit, CoreText, minimal OOXML writer
│   ├── ConvertOptions.swift    quality settings
│   ├── ConvertModel.swift      queue and state
│   └── ConvertView.swift       converter screen
├── Download/
│   ├── DownloadModel.swift     download queue, link checking
│   └── DownloadView.swift      downloader screen
├── CLI/
│   └── SharkCLI.swift          terminal mode of the same binary
└── Design/
    ├── Glass.swift             Liquid Glass with a material fallback
    ├── FinMark.swift           the fin mark: logo, icon, menu bar
    ├── MenuBarItem.swift       status item and file drops onto it
    ├── SettingsView.swift      settings window
    └── RootView.swift          shell, tabs, engine check screen
```

The fin is drawn once in a normalised 100 × 100 space (`FinMark.swift`) and reused everywhere: header logo, menu bar glyph and app icon. The silhouette cannot drift between them.

## Icon

The app draws its own icon; no image file is stored in the repository:

```bash
./build/Shark.app/Contents/MacOS/Shark --make-icon Resources/AppIcon.icns
```

It renders every size up to 1024×1024 through the system `iconutil` and drops a PNG next to it for inspection. `Scripts/build.sh` runs this on every build.

To use your own artwork, place `Resources/AppIcon.icns` yourself and remove the icon step from `Scripts/build.sh`.

## Self-test

```bash
./build/Shark.app/Contents/MacOS/Shark --selftest
```

Runs 31 real conversions across images, documents, audio and video on generated files and prints a report. No interface is opened, which makes it a fast check after touching the engines.

## Notes on packaging

The app is ad-hoc signed and runs unsandboxed: it launches bundled binaries and writes wherever the user points it.

If the engines are missing the app says so and offers two ways out — rebuild with `Scripts/build.sh`, or drop `ffmpeg`, `ffprobe`, `yt-dlp` into `~/Library/Application Support/Shark/Tools/`.

Liquid Glass is used on macOS 26; on macOS 14 and 15 the interface falls back to `.ultraThinMaterial` with the same layout.
