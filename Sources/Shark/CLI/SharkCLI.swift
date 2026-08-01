import Foundation
import AppKit

/// Терминальный режим того же бинарника.
///
/// Отдельной сборки нет намеренно: движки конвертации и построение аргументов
/// yt-dlp здесь ровно те же, что в окне. Разойтись они не могут физически.
@MainActor
enum SharkCLI {

    static let commands = ["convert", "c", "download", "formats", "sources", "info",
                           "man", "help", "version"]

    /// Запускать ли терминальный режим: по имени вызова или по первому аргументу.
    static func shouldRun(_ arguments: [String]) -> Bool {
        let invokedAs = URL(fileURLWithPath: arguments.first ?? "").lastPathComponent
        if invokedAs == "shark" { return true }
        guard let first = arguments.dropFirst().first else { return false }
        return commands.contains(first) || ["--help", "--version", "--list-sources"].contains(first)
    }

    static func run(_ arguments: [String]) async -> Int32 {
        var rest = Array(arguments.dropFirst())
        let command = rest.first ?? "help"
        if !rest.isEmpty { rest.removeFirst() }

        switch command {
        // `c` — короткая форма самой частой команды.
        case "convert", "c": return await convert(rest)
        case "download": return await download(rest)
        case "formats":  return formats(rest)
        case "sources", "--list-sources": return await sources(rest)
        case "info":     return await info(rest)
        case "man":      return await manual()
        // Версию берём из бандла: зашитая строка врала бы после каждого релиза.
        case "version", "--version": out("Shark \(AppUpdater.currentVersion)"); return 0
        case "help", "--help", "-h": out(usage); return 0
        default:
            // Пустой вызов — не ошибка, а просьба показать, что умеет инструмент.
            if command.isEmpty { out(usage); return 0 }
            err("Неизвестная команда: \(command)")
            err("Список команд: shark help")
            return 2
        }
    }

    // MARK: - convert

    private static func convert(_ arguments: [String]) async -> Int32 {
        var options = Options(arguments)
        guard let target = options.value("--to") ?? options.value("-t") else {
            err("Не указан формат. Пример: shark convert video.mov --to mp4")
            return 2
        }
        let inputs = options.positional.map { URL(fileURLWithPath: $0).standardizedFileURL }
        guard !inputs.isEmpty else {
            err("Не указаны файлы.")
            return 2
        }

        var settings = ConvertOptions()
        if let quality = options.value("--quality") {
            switch quality {
            case "high", "max":      settings.videoQuality = .high
            case "balanced":         settings.videoQuality = .balanced
            case "compact", "small": settings.videoQuality = .compact
            default: err("Неизвестное качество: \(quality)"); return 2
            }
        }
        if let resolution = options.value("--resolution") {
            let map: [String: ConvertOptions.Resolution] = [
                "original": .original, "2160": .p2160, "1440": .p1440,
                "1080": .p1080, "720": .p720, "480": .p480, "360": .p360
            ]
            guard let value = map[resolution] else {
                err("Неизвестное разрешение: \(resolution)"); return 2
            }
            settings.resolution = value
        }
        if let bitrate = options.value("--bitrate") {
            guard let number = Int(bitrate),
                  let value = ConvertOptions.AudioBitrate(rawValue: number) else {
                err("Неизвестный битрейт: \(bitrate). Допустимо: 96, 128, 192, 256, 320")
                return 2
            }
            settings.audioBitrate = value
        }
        if let quality = options.value("--image-quality"), let number = Double(quality) {
            settings.imageQuality = max(0, min(1, number / 100))
        }
        settings.stripMetadata = options.flag("--strip-metadata")

        let overwrite = options.flag("--overwrite")
        let directory = options.value("--out").map { URL(fileURLWithPath: $0) }
            ?? options.value("-o").map { URL(fileURLWithPath: $0) }
        let customName = options.value("--name")
        if customName != nil && inputs.count > 1 {
            err("--name работает только с одним файлом.")
            return 2
        }

        if let unknown = options.unknown.first {
            err("Неизвестный параметр: \(unknown)")
            return 2
        }

        var failures = 0
        for source in inputs {
            guard FileManager.default.fileExists(atPath: source.path) else {
                err("Файл не найден: \(source.path)")
                failures += 1
                continue
            }
            let destination = ConversionEngine.destinationURL(
                for: source, target: target, in: directory,
                overwrite: overwrite, baseName: customName)

            let label = source.lastPathComponent
            do {
                try await ConversionEngine.convert(
                    source: source, destination: destination, target: target,
                    options: settings,
                    progress: { value in Progress.draw(label: label, value: value) })
                Progress.finish()
                out(destination.path)
            } catch {
                Progress.finish()
                err("\(label): \(error.localizedDescription)")
                failures += 1
            }
        }
        return failures == 0 ? 0 : 1
    }

    // MARK: - download

    private static func download(_ arguments: [String]) async -> Int32 {
        var options = Options(arguments)
        let urls = options.positional.filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        guard !urls.isEmpty else {
            err("Не указаны ссылки.")
            return 2
        }
        guard let ytdlp = Tools.url(for: .ytdlp) else {
            err(ToolsError.missing(.ytdlp).localizedDescription)
            return 3
        }

        let destination = options.value("--out").map { URL(fileURLWithPath: $0) }
            ?? options.value("-o").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

        var request = DownloadRequest(url: "", destination: destination)
        request.allowPlaylist = options.flag("--playlist")
        request.writeSubtitles = options.flag("--subs")
        request.embedThumbnail = !options.flag("--no-thumbnail")

        if let format = options.value("--audio") {
            guard let value = AudioFormat(rawValue: format) else {
                err("Неизвестный формат звука: \(format)"); return 2
            }
            request.mode = .audio
            request.audioFormat = value
        }
        if let quality = options.value("--quality") {
            let map: [String: DownloadQuality] = [
                "best": .best, "2160": .p2160, "1440": .p1440,
                "1080": .p1080, "720": .p720, "480": .p480
            ]
            guard let value = map[quality] else {
                err("Неизвестное качество: \(quality)"); return 2
            }
            request.quality = value
        }
        if let container = options.value("--container") {
            guard let value = VideoContainer(rawValue: container) else {
                err("Неизвестный контейнер: \(container)"); return 2
            }
            request.container = value
        }
        if let cookies = options.value("--cookies") {
            // Путь к файлу отличаем от имени браузера по наличию такого файла.
            if FileManager.default.fileExists(atPath: cookies) {
                request.cookiesFile = URL(fileURLWithPath: cookies)
            } else if let source = CookieSource(rawValue: cookies), source != .none {
                request.cookies = source
            } else {
                err("Неизвестный источник cookies: \(cookies)")
                return 2
            }
        }

        if let unknown = options.unknown.first {
            err("Неизвестный параметр: \(unknown)")
            return 2
        }

        var failures = 0
        for url in urls {
            request.url = url
            let produced = LockedValue<String?>(nil)
            let label = URL(string: url)?.host ?? url

            do {
                try await ProcessRunner.require(ytdlp, DownloadArguments.build(request)) { line, _ in
                    if let path = DownloadModel.parseDestination(line) { produced.set(path) }
                    if let update = DownloadModel.parseProgress(line) {
                        Progress.draw(label: label, value: update.percent, suffix: update.speed)
                    }
                }
                Progress.finish()
                out(produced.get() ?? url)
            } catch {
                Progress.finish()
                err("\(label): \(DownloadModel.humanize(error.localizedDescription))")
                failures += 1
            }
        }
        return failures == 0 ? 0 : 1
    }

    // MARK: - formats

    private static func formats(_ arguments: [String]) -> Int32 {
        let groups: [(String, [String])] = [
            ("Аудио", Formats.audioTargets),
            ("Видео", Formats.videoTargets),
            ("Изображения", Formats.imageTargets),
            ("Документы", Formats.documentTargets)
        ]
        let filter = arguments.first?.lowercased()
        for (name, list) in groups {
            if let filter, !name.lowercased().hasPrefix(filter) { continue }
            out("\(name):")
            out("  " + list.joined(separator: " "))
        }
        return 0
    }

    // MARK: - man

    /// Показывает страницу руководства прямо из бандла: чтобы `shark man`
    /// работал сразу, не требуя установки в системный путь через sudo.
    private static func manual() async -> Int32 {
        let candidates = [
            // Через ссылку вроде /usr/local/bin/shark это единственный
            // работающий путь: Bundle.main указывает на папку ссылки.
            Tools.bundleContents?.appendingPathComponent("Resources/man/man1/shark.1"),
            Bundle.main.resourceURL?.appendingPathComponent("man/man1/shark.1"),
            Bundle.main.executableURL?.deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/man/man1/shark.1")
        ].compactMap { $0 }

        guard let page = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else {
            err("Страница руководства не найдена в приложении.")
            return 1
        }

        let man = URL(fileURLWithPath: "/usr/bin/man")
        let process = Process()
        process.executableURL = man
        process.arguments = [page.path]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            err(error.localizedDescription)
            return 1
        }
    }

    // MARK: - sources

    /// Список площадок берём у самого yt-dlp: держать свою копию значило бы
    /// расходиться с реальностью после каждого его обновления.
    private static func sources(_ arguments: [String]) async -> Int32 {
        guard let ytdlp = Tools.url(for: .ytdlp) else {
            err(ToolsError.missing(.ytdlp).localizedDescription)
            return 3
        }
        guard let result = try? await ProcessRunner.capture(ytdlp, ["--list-extractors"]),
              result.ok else {
            err("Не удалось получить список источников.")
            return 1
        }

        var lines = result.stdout.split(separator: "\n").map(String.init)
        if let filter = arguments.first?.lowercased() {
            lines = lines.filter { $0.lowercased().contains(filter) }
        }
        lines.forEach { out($0) }
        err("Всего: \(lines.count)")
        return 0
    }

    // MARK: - info

    private static func info(_ arguments: [String]) async -> Int32 {
        guard let path = arguments.first else {
            err("Не указан файл.")
            return 2
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            err("Файл не найден: \(url.path)")
            return 1
        }

        let kind = Formats.kind(of: url)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? nil
        out("файл:       \(url.lastPathComponent)")
        out("тип:        \(kind.rawValue)")
        if let size, let text = formatBytes(size) { out("размер:     \(text)") }

        if kind == .audio || kind == .video {
            let media = await FFmpegConverter.probe(url)
            if let duration = formatDuration(media.duration) { out("длительность: \(duration)") }
            if let width = media.width, let height = media.height {
                out("разрешение: \(width)×\(height)")
            }
            if let codec = media.videoCodec { out("видеокодек: \(codec)") }
            if let codec = media.audioCodec { out("аудиокодек: \(codec)") }
        }
        return 0
    }

    // MARK: - Разбор аргументов

    /// Маленький разборщик: `--ключ значение`, `--флаг` и позиционные аргументы.
    private struct Options {
        private var values: [String: String] = [:]
        private var flags: Set<String> = []
        private(set) var positional: [String] = []
        private var consumed: Set<String> = []

        /// Флаги без значения — их нельзя перепутать с парой «ключ-значение».
        private static let booleans: Set<String> = [
            "--strip-metadata", "--overwrite", "--playlist", "--subs", "--no-thumbnail"
        ]

        init(_ arguments: [String]) {
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                if argument.hasPrefix("-") {
                    if Self.booleans.contains(argument) {
                        flags.insert(argument)
                    } else if index + 1 < arguments.count,
                              !arguments[index + 1].hasPrefix("-") {
                        values[argument] = arguments[index + 1]
                        index += 1
                    } else {
                        flags.insert(argument)
                    }
                } else {
                    positional.append(argument)
                }
                index += 1
            }
        }

        mutating func value(_ key: String) -> String? {
            consumed.insert(key)
            return values[key]
        }

        mutating func flag(_ key: String) -> Bool {
            consumed.insert(key)
            return flags.contains(key)
        }

        /// Всё, о чём команда не спрашивала: молча проглатывать опечатки нельзя.
        var unknown: [String] {
            Array(Set(values.keys).union(flags).subtracting(consumed))
        }
    }

    // MARK: - Вывод

    /// Прогресс идёт в stderr, результат — в stdout: так `shark convert ... > list.txt`
    /// даёт чистый список путей, пригодный для дальнейшей обработки.
    private enum Progress {
        static func draw(label: String, value: Double, suffix: String = "") {
            guard isatty(fileno(stderr)) == 1 else { return }
            let width = 24
            let filled = Int((Double(width) * max(0, min(1, value))).rounded())
            let bar = String(repeating: "█", count: filled)
                + String(repeating: "░", count: width - filled)
            let percent = String(format: "%3d%%", Int(value * 100))
            let tail = suffix.isEmpty ? "" : "  \(suffix)"
            FileHandle.standardError.write(
                Data("\r\(bar) \(percent)  \(label)\(tail)\u{1B}[K".utf8))
        }

        static func finish() {
            guard isatty(fileno(stderr)) == 1 else { return }
            FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
        }
    }

    private static func out(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    private static func err(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    private static let usage = """
    Shark — конвертер файлов и загрузчик видео.

    ИСПОЛЬЗОВАНИЕ
      shark convert <файлы…> --to <формат> [параметры]
      shark c       <файлы…> --to <формат>   — то же самое, короче
      shark download <ссылки…> [параметры]
      shark formats [категория]
      shark sources [фильтр]
      shark info <файл>
      shark man                              — полное руководство

    КОНВЕРТАЦИЯ
      -t, --to <формат>        во что превращать (обязательно)
      -o, --out <папка>        куда класть результат
          --name <имя>         имя результата без расширения (один файл)
          --quality <режим>    high | balanced | compact
          --resolution <высота> original | 2160 | 1440 | 1080 | 720 | 480 | 360
          --bitrate <кбит/с>   96 | 128 | 192 | 256 | 320
          --image-quality <0-100>
          --strip-metadata     удалить метаданные
          --overwrite          перезаписывать существующие файлы

    ЗАГРУЗКА
      -o, --out <папка>        куда сохранять
          --audio <формат>     только звук: mp3 | m4a | opus | flac | wav
          --quality <высота>   best | 2160 | 1440 | 1080 | 720 | 480
          --container <тип>    mp4 | mkv | webm
          --cookies <источник> safari | chrome | firefox | edge | путь к cookies.txt
          --subs               субтитры ru/en
          --playlist           плейлист целиком
          --no-thumbnail       без обложки

    ПРИМЕРЫ
      shark c clip.mov --to mp4 --quality high
      shark convert *.heic --to jpg --image-quality 90 --out ~/Pictures
      shark convert doc.docx --to pdf
      shark download https://example.com/watch?v=… --quality 1080
      shark download https://example.com/watch?v=… --audio mp3

    Пути результатов печатаются в stdout, прогресс — в stderr.
    """
}
