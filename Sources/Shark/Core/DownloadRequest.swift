import Foundation

/// Всё, что нужно для одной загрузки. Существует, чтобы окно и CLI строили
/// аргументы yt-dlp одним и тем же кодом: разъехавшиеся наборы флагов
/// означали бы, что в терминале и в окне получаются разные файлы.
struct DownloadRequest: Sendable {
    var url: String
    var destination: URL
    var mode: DownloadMode = .video
    var quality: DownloadQuality = .p1080
    var audioFormat: AudioFormat = .mp3
    var container: VideoContainer = .mp4
    var cookies: CookieSource = .none
    var cookiesFile: URL?
    var embedThumbnail = true
    var writeSubtitles = false
    var allowPlaylist = false
}

enum DownloadArguments {

    /// Аргументы самой загрузки.
    static func build(_ request: DownloadRequest) -> [String] {
        // --restrict-filenames намеренно не используем: он вырезает всё
        // не-ASCII, и русские названия превращались бы в набор подчёркиваний.
        var args = ["--newline", "--no-warnings", "--no-mtime",
                    "--retries", "5", "--fragment-retries", "10", "--concurrent-fragments", "4"]

        args += request.allowPlaylist ? ["--yes-playlist"] : ["--no-playlist"]
        args += common(request)

        let template = request.allowPlaylist
            ? "%(playlist_title,uploader|Downloads)s/%(playlist_index&{} - |)s%(title).180B.%(ext)s"
            : "%(title).180B.%(ext)s"
        args += ["-P", request.destination.path, "-o", template]

        switch request.mode {
        case .audio:
            args += ["-f", "bestaudio/best", "-x",
                     "--audio-format", request.audioFormat.rawValue,
                     "--audio-quality", "0"]
            if request.embedThumbnail
                && (request.audioFormat == .mp3 || request.audioFormat == .m4a) {
                args += ["--embed-thumbnail"]
            }
            args += ["--add-metadata"]

        case .video:
            let heightFilter = request.quality.height.map { "[height<=\($0)]" } ?? ""
            // Сначала «лучшее видео + лучший звук», потом одиночный поток:
            // выше 360p YouTube раздаёт дорожки порознь.
            args += ["-f", "bv*\(heightFilter)+ba/b\(heightFilter)/bv*+ba/b",
                     "--merge-output-format", request.container.rawValue]
            if request.container == .mp4 {
                // Гарантируем совместимость с QuickTime.
                args += ["--remux-video", "mp4"]
            }
            if request.embedThumbnail { args += ["--embed-thumbnail"] }
            if request.writeSubtitles {
                args += ["--write-subs", "--write-auto-subs", "--sub-langs", "ru,en", "--embed-subs"]
            }
            args += ["--add-metadata"]
        }

        args.append(request.url)
        return args
    }

    /// Аргументы разведки: те же движки и те же cookies, что и у загрузки.
    /// Иначе проверка сообщала бы об отказе там, где скачивание бы прошло.
    static func probe(_ request: DownloadRequest) -> [String] {
        var args = ["--dump-single-json", "--no-warnings", "--no-playlist",
                    "--flat-playlist", "--socket-timeout", "15"]
        args += common(request)
        args.append(request.url)
        return args
    }

    private static func common(_ request: DownloadRequest) -> [String] {
        var args: [String] = []
        if let ffmpegDir = Tools.ffmpegDirectory {
            args += ["--ffmpeg-location", ffmpegDir.path]
        }
        // YouTube требует исполнить свой JS, чтобы расшифровать ссылки на потоки.
        if let deno = Tools.url(for: .deno) {
            args += ["--js-runtimes", "deno:\(deno.path)"]
        }
        // Явно выбранный файл важнее выпадающего списка: он и точнее, и надёжнее.
        if let file = request.cookiesFile {
            args += ["--cookies", file.path]
        } else if let browser = request.cookies.ytdlpValue {
            args += ["--cookies-from-browser", browser]
        }
        return args
    }
}
