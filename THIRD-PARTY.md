# Third-party components

Shark bundles four binaries that are fetched at build time by
`Scripts/fetch-tools.sh`. They are not part of this repository and keep their
own licences.

| Component | Purpose | Licence |
|---|---|---|
| [ffmpeg / ffprobe](https://ffmpeg.org) | audio and video conversion, merging downloaded streams | LGPL-2.1-or-later or GPL-2.0-or-later, depending on the build |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | downloading video and audio | Unlicense |
| [deno](https://deno.com) | JavaScript runtime that yt-dlp needs for YouTube | MIT |

Shark itself is MIT licensed and calls these tools as separate processes rather
than linking against them.
