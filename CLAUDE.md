# Shark — project notes

## Commits

All commits are authored by the repository owner:

```
Arseny <abs0ss1007@gmail.com>
```

Do **not** add `Co-Authored-By` trailers of any kind, and do not mention the
tooling used to write the code in commit messages. The identity is also set in
the repository's local git config, so plain `git commit` already does the right
thing.

Commit messages: a short imperative subject line, then a body explaining *why*
the change was made and what it fixes. Prefer describing the defect and its
consequence over listing the files touched.

## Architecture in one paragraph

One SwiftUI app and one CLI live in the **same binary**. `main.swift` inspects
the invocation name and the first argument, then routes to the window, the CLI,
the self-test or the icon generator. This is deliberate: conversion in the
terminal and in the window cannot drift apart because the code is shared. Never
split the CLI into a separate target.

## Rules that came from real defects

- **Never look up bundle paths through `Bundle.main` alone.** When the CLI is
  reached through a symlink such as `/usr/local/bin/shark`, `Bundle.main` points
  at the link's directory. Use `Tools.bundleContents`, which resolves symlinks
  first. Getting this wrong silently breaks every engine.
- **The filesystem is case-insensitive.** `shark` and `Shark` are the same name;
  that is why the CLI symlink lives in `Contents/Helpers`, not `Contents/MacOS`.
- **Document conversion must run on the main thread.** The AppKit importers hop
  to the main thread internally and deadlock when called from a background
  queue. `DocumentConverter` is `@MainActor` for that reason.
- **A chosen output format applies only where it is offered.** Applying one
  target to a whole mixed queue produced documents "converted" to MP4.
- **Engines are looked up in Application Support first**, then the bundle. The
  bundled copies are the baseline; updates override them.

## Verification

```bash
INSTALL=1 bash Scripts/build.sh
/Applications/Shark.app/Contents/MacOS/Shark --selftest
```

The self-test runs 31 real conversions on generated files. Run it after any
change to the conversion path — it has caught regressions that a clean build
did not.

For anything touching the CLI, test through an installed symlink rather than
the bundle path directly; several defects only appear that way.

## Releases

```bash
bash Scripts/release.sh <version>
```

Builds, packs with `ditto` (which preserves the symlinks inside the bundle —
plain `zip` corrupts them), publishes a GitHub release and prints the sha256
for the Homebrew cask in `shineexxx/homebrew-tap`.

## Localisation

The interface ships in English and Russian. Translations are a Swift table in
`Localization.swift`, keyed by the English string itself, so a missing entry
degrades into English rather than an identifier. User-facing strings must go
through `L("…")`; hardcoding was how "VK Видео" ended up in the English UI.
